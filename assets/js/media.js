/* Media — a free image per option, looked up on Wikipedia.
 *
 * One batched request per session pool against the pageimages API (no key,
 * CORS-enabled, up to 50 titles a call). Results are cached in localStorage
 * for 30 days, misses included, so a topic is fetched once per browser.
 *
 * Only images hosted on Wikimedia Commons are used, because those carry free
 * licences. Files kept locally on en.wikipedia — film posters, album covers —
 * are usually non-free and are skipped; a card without an image just shows its
 * name, which the layout is built for. Flip `config.freeOnly` to change that.
 *
 * Every path degrades to "no image": no fetch(), no network, a blocked host, a
 * missing article. Nothing here is on the critical path for ranking.
 */
(function (global) {
  'use strict';

  var ENDPOINT = 'https://en.wikipedia.org/w/api.php';
  var PAGE_BASE = 'https://en.wikipedia.org/wiki/';
  var THUMB_PX = 640;
  var TTL_MS = 30 * 24 * 60 * 60 * 1000;
  var BATCH = 50;                    // the API's per-request title limit
  var RETRY_AFTER_MS = 60 * 1000;    // back off after a failed request

  var config = { enabled: true, freeOnly: true };
  var cache = null;
  var inFlight = {};
  var blockedUntil = 0;
  var listeners = [];

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

  /* The lookup key: the explicit article title when the name is ambiguous. */
  function titleOf(item) {
    return String((item && (item.wiki || item.name)) || '').trim();
  }

  function isFree(url) {
    return /\/wikipedia\/commons\//.test(String(url));
  }

  function requestUrl(titles) {
    return ENDPOINT + '?action=query&format=json&formatversion=2&origin=*&redirects=1'
      + '&prop=pageimages&piprop=thumbnail&pithumbsize=' + THUMB_PX
      + '&titles=' + encodeURIComponent(titles.join('|'));
  }

  /* Maps each requested title to { url, page }, following the normalisation
   * and redirect hops the API reports so "Xavi" still finds its page. */
  function parseResponse(json, titles) {
    var query = (json && json.query) || {};
    var hop = {};
    (query.normalized || []).concat(query.redirects || []).forEach(function (r) {
      hop[r.from] = r.to;
    });
    var byTitle = {};
    (query.pages || []).forEach(function (page) { byTitle[page.title] = page; });

    var out = {};
    titles.forEach(function (title) {
      var finalTitle = title;
      for (var guard = 0; hop[finalTitle] && guard < 5; guard++) finalTitle = hop[finalTitle];
      var page = byTitle[finalTitle];
      var url = page && page.thumbnail && page.thumbnail.source ? page.thumbnail.source : null;
      if (url && config.freeOnly && !isFree(url)) url = null;
      out[title] = {
        url: url,
        page: page && !page.missing ? page.title : null
      };
    });
    return out;
  }

  function fresh(entry) {
    return !!entry && (Date.now() - (entry.ts || 0)) < TTL_MS;
  }

  /* Synchronous, cache-only. Call prefetch() first; re-render on change. */
  function get(item) {
    if (!config.enabled) return null;
    var entry = entries()[titleOf(item)];
    return fresh(entry) ? entry.url : null;
  }

  /* The article an image came from, for attribution. */
  function pageUrl(item) {
    var entry = entries()[titleOf(item)];
    var page = entry && entry.page;
    return page ? PAGE_BASE + encodeURIComponent(page.replace(/ /g, '_')) : null;
  }

  function onChange(fn) { listeners.push(fn); }

  function notify() {
    listeners.forEach(function (fn) {
      try { fn(); } catch (err) { /* one bad listener must not stop the rest */ }
    });
  }

  function prefetch(items) {
    if (!config.enabled || typeof global.fetch !== 'function') return 0;
    if (Date.now() < blockedUntil) return 0;

    var need = [];
    var seen = {};
    (items || []).forEach(function (item) {
      var title = titleOf(item);
      if (!title || seen[title] || inFlight[title] || fresh(entries()[title])) return;
      seen[title] = true;
      need.push(title);
    });
    for (var i = 0; i < need.length; i += BATCH) fetchBatch(need.slice(i, i + BATCH));
    return need.length;
  }

  function fetchBatch(titles) {
    titles.forEach(function (title) { inFlight[title] = true; });
    global.fetch(requestUrl(titles), { mode: 'cors' })
      .then(function (response) {
        if (!response.ok) throw new Error('HTTP ' + response.status);
        return response.json();
      })
      .then(function (json) {
        var found = parseResponse(json, titles);
        var now = Date.now();
        titles.forEach(function (title) {
          entries()[title] = { url: found[title].url, page: found[title].page, ts: now };
        });
        storage().saveMediaCache(entries());
        notify();
      })
      .catch(function () {
        blockedUntil = Date.now() + RETRY_AFTER_MS;
      })
      .then(function () {
        titles.forEach(function (title) { delete inFlight[title]; });
      });
  }

  var Media = {
    config: config,
    get: get,
    pageUrl: pageUrl,
    prefetch: prefetch,
    onChange: onChange,
    /* exposed for tests */
    titleOf: titleOf,
    isFree: isFree,
    requestUrl: requestUrl,
    parseResponse: parseResponse,
    _reset: function () { cache = null; inFlight = {}; blockedUntil = 0; listeners = []; }
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = Media;
  global.Media = Media;
})(typeof globalThis !== 'undefined' ? globalThis : this);
