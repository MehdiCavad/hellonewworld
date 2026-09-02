/* Media — an image, a link and sometimes a sound clip per option.
 *
 * Two sources, chosen per topic:
 *
 *   wikipedia       Free photos from Wikimedia Commons via the pageimages API.
 *                   One batched request per pool (50 titles a call, CORS via
 *                   origin=*). Only Commons-hosted files are used: those carry
 *                   free licences, while posters kept locally on en.wikipedia
 *                   are usually non-free. People, places, food, languages.
 *
 *   itunes:<entity> Store artwork from the iTunes Search API — film posters,
 *                   TV season art, album covers — plus the 30-second preview
 *                   Apple serves for songs. No key. Loaded as JSONP so it does
 *                   not depend on CORS. One request per option, spaced out
 *                   because the API rate-limits bursts, current pair first.
 *
 * Results are cached in localStorage for 30 days, misses included, keyed by
 * source and query, so a topic is fetched once per browser. Every path
 * degrades to "no media": nothing here is on the ranking's critical path.
 */
(function (global) {
  'use strict';

  var TTL_MS = 30 * 24 * 60 * 60 * 1000;
  var RETRY_AFTER_MS = 60 * 1000;
  var WIKI_ENDPOINT = 'https://en.wikipedia.org/w/api.php';
  var WIKI_PAGE = 'https://en.wikipedia.org/wiki/';
  var WIKI_BATCH = 50;
  var WIKI_THUMB = 640;
  var ITUNES_ENDPOINT = 'https://itunes.apple.com/search';
  var ITUNES_SPACING_MS = 220;     // ~20 requests a minute is the documented ceiling for bursts
  var ITUNES_TIMEOUT_MS = 8000;

  var ITUNES = {
    'itunes:song':     { entity: 'song',     media: 'music',  shape: 'square' },
    'itunes:movie':    { entity: 'movie',    media: 'movie',  shape: 'poster' },
    'itunes:tvSeason': { entity: 'tvSeason', media: 'tvShow', shape: 'poster' }
  };

  var config = { enabled: true, freeOnly: true };
  var cache = null;
  var inFlight = {};
  var blockedUntil = {};
  var listeners = [];
  var itunesQueue = [];
  var itunesTimer = null;
  var jsonpSeq = 0;

  /* ---- storage ---------------------------------------------------------- */

  function storage() {
    return global.Storage || {
      mediaCache: function () { return {}; },
      saveMediaCache: function () {}
    };
  }
  function entries() {
    if (!cache) cache = storage().mediaCache();
    return cache;
  }
  function fresh(entry) {
    return !!entry && (Date.now() - (entry.ts || 0)) < TTL_MS;
  }
  function remember(key, entry) {
    entry.ts = Date.now();
    entries()[key] = entry;
  }
  function flush() {
    storage().saveMediaCache(entries());
    notify();
  }

  /* ---- keys ------------------------------------------------------------- */

  function kindOf(kind) {
    return ITUNES[kind] ? kind : 'wikipedia';
  }

  /* What we ask the source for. Wikipedia wants an article title, so an
   * explicit one wins over the display name. iTunes wants a search phrase, and
   * "title + year" or "title + artist" is the phrase that finds the right one. */
  function queryFor(item, kind) {
    if (!item) return '';
    if (ITUNES[kindOf(kind)]) {
      return String(item.name + ' ' + (item.meta || '')).trim();
    }
    return String(item.wiki || item.name || '').trim();
  }

  function keyFor(item, kind) {
    return kindOf(kind) + '|' + queryFor(item, kind);
  }

  function shape(kind) {
    var k = ITUNES[kindOf(kind)];
    return k ? k.shape : 'portrait';
  }

  /* ---- reads (synchronous, cache only) ---------------------------------- */

  function lookup(item, kind) {
    if (!config.enabled) return null;
    var entry = entries()[keyFor(item, kind)];
    return fresh(entry) ? entry : null;
  }
  function get(item, kind)   { var e = lookup(item, kind); return e ? e.url   || null : null; }
  function audio(item, kind) { var e = lookup(item, kind); return e ? e.audio || null : null; }
  function link(item, kind)  { var e = lookup(item, kind); return e ? e.link  || null : null; }

  function onChange(fn) { listeners.push(fn); }
  function notify() {
    listeners.forEach(function (fn) {
      try { fn(); } catch (err) { /* one bad listener must not stop the rest */ }
    });
  }

  /* ---- wikipedia -------------------------------------------------------- */

  function isFree(url) {
    return /\/wikipedia\/commons\//.test(String(url));
  }

  function wikiRequestUrl(titles) {
    return WIKI_ENDPOINT + '?action=query&format=json&formatversion=2&origin=*&redirects=1'
      + '&prop=pageimages&piprop=thumbnail&pithumbsize=' + WIKI_THUMB
      + '&titles=' + encodeURIComponent(titles.join('|'));
  }

  /* Maps each requested title to { url, link }, following the normalisation
   * and redirect hops the API reports so "Xavi" still finds its page. */
  function wikiParse(json, titles) {
    var query = (json && json.query) || {};
    var hop = {};
    (query.normalized || []).concat(query.redirects || []).forEach(function (r) { hop[r.from] = r.to; });
    var byTitle = {};
    (query.pages || []).forEach(function (page) { byTitle[page.title] = page; });

    var out = {};
    titles.forEach(function (title) {
      var finalTitle = title;
      for (var guard = 0; hop[finalTitle] && guard < 5; guard++) finalTitle = hop[finalTitle];
      var page = byTitle[finalTitle];
      var url = page && page.thumbnail && page.thumbnail.source ? page.thumbnail.source : null;
      if (url && config.freeOnly && !isFree(url)) url = null;
      var exists = page && !page.missing;
      out[title] = {
        url: url,
        link: exists ? WIKI_PAGE + encodeURIComponent(page.title.replace(/ /g, '_')) : null
      };
    });
    return out;
  }

  function wikiFetch(titles) {
    titles.forEach(function (t) { inFlight['wikipedia|' + t] = true; });
    global.fetch(wikiRequestUrl(titles), { mode: 'cors' })
      .then(function (response) {
        if (!response.ok) throw new Error('HTTP ' + response.status);
        return response.json();
      })
      .then(function (json) {
        var found = wikiParse(json, titles);
        titles.forEach(function (t) { remember('wikipedia|' + t, found[t]); });
        flush();
      })
      .catch(function () { blockedUntil.wikipedia = Date.now() + RETRY_AFTER_MS; })
      .then(function () { titles.forEach(function (t) { delete inFlight['wikipedia|' + t]; }); });
  }

  /* ---- itunes ----------------------------------------------------------- */

  function itunesRequestUrl(query, kind, callbackName) {
    var k = ITUNES[kind];
    return ITUNES_ENDPOINT + '?term=' + encodeURIComponent(query)
      + '&entity=' + k.entity + '&media=' + k.media + '&limit=1&country=us'
      + (callbackName ? '&callback=' + callbackName : '');
  }

  /* Artwork comes back at 100px; the same path serves larger renditions. */
  function itunesParse(json) {
    var hit = json && json.results && json.results[0];
    if (!hit) return { url: null, link: null, audio: null };
    var art = hit.artworkUrl100 || hit.artworkUrl60 || null;
    return {
      url: art ? art.replace(/\/\d+x\d+bb\./, '/600x600bb.') : null,
      link: hit.trackViewUrl || hit.collectionViewUrl || null,
      audio: hit.previewUrl || null
    };
  }

  /* JSONP: a <script> tag the API answers by calling back into. Works from any
   * origin, which is why it is used here instead of fetch(). */
  function jsonp(url, done) {
    var doc = global.document;
    if (!doc) return done(null);
    var name = '__rankdMedia' + (++jsonpSeq);
    var script = doc.createElement('script');
    var timer = global.setTimeout(function () { finish(null); }, ITUNES_TIMEOUT_MS);
    function finish(json) {
      global.clearTimeout(timer);
      try { delete global[name]; } catch (e) { global[name] = undefined; }
      if (script.parentNode) script.parentNode.removeChild(script);
      done(json);
    }
    global[name] = function (json) { finish(json); };
    script.onerror = function () { finish(null); };
    script.src = url.replace('callback=' + '__CB__', 'callback=' + name);
    doc.head.appendChild(script);
  }

  function itunesEnqueue(query, kind) {
    itunesQueue.push({ query: query, kind: kind });
    if (!itunesTimer) itunesDrain();
  }

  function itunesDrain() {
    var job = itunesQueue.shift();
    if (!job) { itunesTimer = null; return; }
    var key = job.kind + '|' + job.query;
    jsonp(itunesRequestUrl(job.query, job.kind, '__CB__'), function (json) {
      if (json) {
        remember(key, itunesParse(json));
        flush();
      } else {
        /* A timeout or error: stop hammering, let the rest retry later. */
        blockedUntil[job.kind] = Date.now() + RETRY_AFTER_MS;
        itunesQueue = itunesQueue.filter(function (j) { return j.kind !== job.kind; });
      }
      delete inFlight[key];
    });
    itunesTimer = global.setTimeout(itunesDrain, ITUNES_SPACING_MS);
  }

  /* ---- prefetch ------------------------------------------------------- */

  /* Queues lookups for whatever is not cached, in the order given, so callers
   * can put the options on screen first. Returns how many were queued. */
  function prefetch(items, kind) {
    kind = kindOf(kind);
    if (!config.enabled || !global.document) return 0;
    if (Date.now() < (blockedUntil[kind] || 0)) return 0;

    var need = [];
    var seen = {};
    (items || []).forEach(function (item) {
      var query = queryFor(item, kind);
      var key = kind + '|' + query;
      if (!query || seen[key] || inFlight[key] || fresh(entries()[key])) return;
      seen[key] = true;
      need.push(query);
    });
    if (!need.length) return 0;

    if (ITUNES[kind]) {
      need.forEach(function (q) { inFlight[kind + '|' + q] = true; itunesEnqueue(q, kind); });
    } else if (typeof global.fetch === 'function') {
      for (var i = 0; i < need.length; i += WIKI_BATCH) wikiFetch(need.slice(i, i + WIKI_BATCH));
    } else {
      return 0;
    }
    return need.length;
  }

  var Media = {
    config: config,
    get: get,
    audio: audio,
    link: link,
    shape: shape,
    prefetch: prefetch,
    onChange: onChange,
    /* exposed for tests */
    kindOf: kindOf,
    queryFor: queryFor,
    keyFor: keyFor,
    isFree: isFree,
    wikiRequestUrl: wikiRequestUrl,
    wikiParse: wikiParse,
    itunesRequestUrl: itunesRequestUrl,
    itunesParse: itunesParse,
    _reset: function () {
      cache = null; inFlight = {}; blockedUntil = {}; listeners = [];
      itunesQueue = []; if (itunesTimer) global.clearTimeout(itunesTimer); itunesTimer = null;
    }
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = Media;
  global.Media = Media;
})(typeof globalThis !== 'undefined' ? globalThis : this);
