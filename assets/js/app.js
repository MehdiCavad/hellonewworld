/* UI layer: hash routing, rendering and input handling.
 *
 * Routes:
 *   #/                    topic picker
 *   #/topic/<topicId>     level and style picker
 *   #/play/<sessionId>    the duel screen
 *   #/result/<sessionId>  the finished ranking
 */
(function () {
  'use strict';

  var el = function (id) { return document.getElementById(id); };

  var state = { topic: null, level: Data.getLevel('standard'), mode: 'smart', session: null };

  /* ---------- helpers ---------- */

  function escapeHtml(value) {
    return String(value === null || value === undefined ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  function allTopics() {
    return Data.topics.concat(Storage.customTopics());
  }

  function findTopic(id) {
    var list = allTopics();
    for (var i = 0; i < list.length; i++) {
      if (list[i].id === id) return list[i];
    }
    return null;
  }

  var toastTimer = null;
  function toast(message) {
    var node = el('toast');
    node.textContent = message;
    node.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { node.hidden = true; }, 2200);
  }

  function go(route) {
    if (location.hash === route) render();
    else location.hash = route;
  }

  function plural(count, word) {
    return count + ' ' + word + (count === 1 ? '' : 's');
  }

  function timeAgo(ts) {
    var seconds = Math.max(1, Math.round((Date.now() - ts) / 1000));
    if (seconds < 60) return 'just now';
    var minutes = Math.round(seconds / 60);
    if (minutes < 60) return plural(minutes, 'minute') + ' ago';
    var hours = Math.round(minutes / 60);
    if (hours < 24) return plural(hours, 'hour') + ' ago';
    return plural(Math.round(hours / 24), 'day') + ' ago';
  }

  /* ---------- home ---------- */

  function renderHome() {
    var grid = el('topicGrid');
    grid.innerHTML = allTopics().map(function (topic) {
      var count = topic.items.length;
      return '<button class="card" data-topic="' + escapeHtml(topic.id) + '">' +
        '<span class="card-emoji">' + escapeHtml(topic.emoji) + '</span>' +
        '<span class="card-name">' + escapeHtml(topic.name) + '</span>' +
        '<span class="card-sub">' + escapeHtml(topic.blurb) + ' · ' + count + ' options</span>' +
        '</button>';
    }).join('');

    var sessions = Storage.allSessions();
    var active = sessions.filter(function (s) { return !s.finished && s.history.length > 0; });
    var done = sessions.filter(function (s) { return s.finished; });

    el('resumeSection').hidden = active.length === 0;
    el('resumeList').innerHTML = active.map(function (session) {
      var progress = Engine.progress(session);
      return rowCard(session, 'play', Math.round(progress.ratio * 100) + '% done · ' +
        progress.remaining + ' rounds left · ' + timeAgo(session.updatedAt));
    }).join('');

    el('resultsSection').hidden = done.length === 0;
    el('resultsList').innerHTML = done.map(function (session) {
      var top = Engine.standings(session)[0];
      return rowCard(session, 'result', '🥇 ' + escapeHtml(top ? top.name : '—') +
        ' · ' + plural(session.history.length, 'comparison') + ' · ' + timeAgo(session.updatedAt));
    }).join('');

    el('storageNote').textContent = Storage.persistent
      ? 'Your rankings are saved in this browser only — nothing is uploaded anywhere.'
      : 'Storage is blocked in this browser, so rankings will be lost when you close the tab.';
  }

  function rowCard(session, route, subtitle) {
    return '<button class="row-card" data-go="#/' + route + '/' + escapeHtml(session.id) + '">' +
      '<span class="row-emoji">' + escapeHtml(session.topicEmoji || '⭐') + '</span>' +
      '<span class="row-main">' +
        '<span class="row-title">' + escapeHtml(session.topicName) + ' · ' + escapeHtml(session.levelName) + '</span>' +
        '<span class="row-sub">' + subtitle + '</span>' +
      '</span>' +
      '<span class="row-go">›</span>' +
      '</button>';
  }

  /* ---------- level picker ---------- */

  function renderLevel() {
    var topic = state.topic;
    el('levelHead').innerHTML =
      '<span class="head-emoji">' + escapeHtml(topic.emoji) + '</span>' +
      '<span><h1>' + escapeHtml(topic.name) + '</h1>' +
      '<span class="head-sub">' + escapeHtml(topic.blurb) + '</span></span>';

    el('levelGrid').innerHTML = Data.levels.map(function (level) {
      var size = Data.countForLevel(topic, level);
      var rounds = Data.roundsFor(level, size);
      var disabled = size < 2;
      return '<button class="card' + (level.id === state.level.id ? ' selected' : '') + '"' +
        (disabled ? ' disabled' : '') + ' data-level="' + level.id + '">' +
        '<span class="card-emoji">' + level.emoji + '</span>' +
        '<span class="card-name">' + level.name + '</span>' +
        '<span class="card-sub">' + escapeHtml(level.blurb) + '</span>' +
        '<span class="level-stat"><span><b>' + size + '</b> options</span>' +
        '<span>about <b>' + rounds + '</b> taps</span></span>' +
        '</button>';
    }).join('');

    var modes = [
      { id: 'smart', name: 'Smart duels', blurb: 'The app picks the pair it is least sure about. Fewest taps for the sharpest ranking.' },
      { id: 'gauntlet', name: 'King of the hill', blurb: 'Your winner stays on and defends against a new challenger each round.' }
    ];
    el('modeGrid').innerHTML = modes.map(function (mode) {
      return '<button class="card' + (mode.id === state.mode ? ' selected' : '') + '" data-mode="' + mode.id + '">' +
        '<span class="card-name">' + mode.name + '</span>' +
        '<span class="card-sub">' + mode.blurb + '</span></button>';
    }).join('');
  }

  function startSession() {
    var topic = state.topic;
    var level = state.level;
    var seed = Math.floor(Math.random() * 1e9);
    var pool = Data.buildPool(topic, level, Engine.makeRng(seed));
    if (pool.length < 2) {
      toast('This topic needs at least two options.');
      return;
    }
    var session = Engine.createSession({
      topicId: topic.id,
      topicName: topic.name,
      topicEmoji: topic.emoji,
      levelId: level.id,
      levelName: level.name,
      mode: state.mode,
      mediaKind: topic.media || 'wikipedia',
      items: pool,
      targetRounds: Data.roundsFor(level, pool.length),
      seed: seed
    });
    Storage.saveSession(session);
    Storage.savePrefs({ mode: state.mode, level: level.id });
    state.session = session;
    go('#/play/' + session.id);
  }

  /* ---------- arena ---------- */

  function renderArena() {
    var session = state.session;
    if (session.finished || !session.current) {
      go('#/result/' + session.id);
      return;
    }

    var progress = Engine.progress(session);
    el('roundLabel').textContent = 'Round ' + (progress.rounds + 1) + ' of ' + progress.target;
    el('coverageLabel').textContent = progress.coverage < 1
      ? 'warming up'
      : Math.round(progress.ratio * 100) + '% complete';
    el('progressBar').style.width = (progress.ratio * 100) + '%';
    el('promptLabel').textContent = session.mode === 'gauntlet' && session.champion
      ? 'Can the challenger beat your pick?'
      : 'Which one do you prefer?';

    renderOption(el('optionA'), session.items[session.current[0]], '←');
    renderOption(el('optionB'), session.items[session.current[1]], '→');
    markChampion(el('optionA'));
    markChampion(el('optionB'));

    el('undoBtn').disabled = session.history.length === 0;
    el('finishBtn').disabled = session.history.length < 3;

    var top = Engine.standings(session).slice(0, 5);
    el('peekList').innerHTML = top.map(function (row) {
      return '<li><b>' + escapeHtml(row.name) + '</b> · ' + row.wins + 'W ' + row.losses + 'L</li>';
    }).join('') || '<li>No comparisons yet.</li>';
  }

  function renderOption(node, item, key) {
    var kind = state.session.mediaKind;
    var media = Media.get(item, kind);
    var clip = Media.audio(item, kind);
    node.className = 'option' + (media ? ' has-media' : '');
    node.dataset.id = item.id;
    node.innerHTML =
      '<span class="option-key">' + key + '</span>' +
      (media ? artHtml(media, clip, kind) : '') +
      '<span class="option-name">' + escapeHtml(item.name) + '</span>' +
      (item.meta ? '<span class="option-meta">' + escapeHtml(item.meta) + '</span>' : '');
  }

  /* In king of the hill the champion holds its slot, so flag which card is
   * the one staying put. renderOption resets className, so call this after. */
  function markChampion(node) {
    var session = state.session;
    if (session.mode === 'gauntlet' && session.champion && node.dataset.id === session.champion) {
      node.classList.add('is-champion');
    }
  }

  /* Media arriving must not re-render the arena wholesale: results trickle in
   * every few hundred milliseconds, and a full re-render each time would wipe
   * keyboard focus and a playing preview's progress. Only a card whose media
   * state actually changed is redrawn, and that happens once per card. */
  function refreshArenaMedia() {
    var session = state.session;
    if (!session || !session.current) return;
    [['optionA', 0, '←'], ['optionB', 1, '→']].forEach(function (slot) {
      var node = el(slot[0]);
      var item = session.items[session.current[slot[1]]];
      var hasMedia = !!Media.get(item, session.mediaKind);
      if (hasMedia !== !!node.querySelector('.option-media')) {
        renderOption(node, item, slot[2]);
        markChampion(node);
      }
    });
    syncPreviewUi();
  }

  var PLAY_GLYPHS =
    '<svg class="play-glyph" viewBox="0 0 12 12" aria-hidden="true"><path d="M3 1.5v9l7.5-4.5z"/></svg>' +
    '<svg class="stop-glyph" viewBox="0 0 12 12" aria-hidden="true"><rect x="2.5" y="2.5" width="7" height="7"/></svg>';

  function artHtml(media, clip, kind) {
    return '<span class="option-art' + (clip ? ' has-progress' : '') + '">' +
      '<img class="option-media" data-shape="' + Media.shape(kind) + '" src="' + escapeHtml(media) + '" alt="" loading="eager">' +
      (clip
        ? '<span class="play" role="button" tabindex="0" aria-label="Play preview" data-clip="' + escapeHtml(clip) + '">' +
            PLAY_GLYPHS + '</span><span class="play-progress"></span>'
        : '') +
      '</span>';
  }

  /* ---------- song previews ----------
   * One shared <audio>. The control sits inside the option button, so its
   * clicks are intercepted in onOptionClick before they can count as a pick. */
  var player = null;

  function getPlayer() {
    if (player) return player;
    player = new Audio();
    player.preload = 'none';
    player.hidden = true;
    document.body.appendChild(player);   // in the tree so devtools and tests can see it
    player.addEventListener('timeupdate', function () {
      var btn = document.querySelector('.play.playing');
      if (btn && player.duration) btn.parentNode.style.setProperty('--p', player.currentTime / player.duration);
    });
    player.addEventListener('ended', stopPreview);
    player.addEventListener('error', stopPreview);
    return player;
  }

  function stopPreview() {
    if (player && !player.paused) player.pause();
    var btn = document.querySelector('.play.playing');
    if (btn) {
      btn.classList.remove('playing');
      btn.setAttribute('aria-label', 'Play preview');
      btn.parentNode.style.removeProperty('--p');
    }
  }

  function togglePreview(btn) {
    var wasPlaying = btn.classList.contains('playing');
    stopPreview();
    if (wasPlaying) return;
    var audioEl = getPlayer();
    if (audioEl.src !== btn.dataset.clip) audioEl.src = btn.dataset.clip;
    audioEl.currentTime = 0;
    btn.classList.add('playing');
    btn.setAttribute('aria-label', 'Stop preview');
    var started = audioEl.play();
    if (started && started.catch) started.catch(stopPreview);
  }

  /* After a re-render (images arriving), put the playing state back on the
   * control whose clip is still sounding. */
  function syncPreviewUi() {
    if (!player || player.paused) return;
    var buttons = document.querySelectorAll('.play');
    for (var i = 0; i < buttons.length; i++) {
      if (buttons[i].dataset.clip === player.src) {
        buttons[i].classList.add('playing');
        buttons[i].setAttribute('aria-label', 'Stop preview');
      }
    }
  }

  function onOptionClick(event) {
    var play = event.target.closest('.play');
    if (play) {
      event.preventDefault();
      togglePreview(play);
      return;
    }
    choose(this.dataset.id);
  }

  /* Answers are applied synchronously. An earlier version held a lock while a
   * short "you picked this" animation played, which silently swallowed any tap
   * or keypress landing inside that window — the worst possible failure for a
   * ranking app, because the answer looks accepted. Feedback is now purely
   * visual: the incoming pair animates in and nothing gates the input. */
  function choose(winnerId) {
    var session = state.session;
    if (!session || !session.current) return;

    stopPreview();
    Engine.submit(session, winnerId);
    Storage.saveSession(session);
    if (session.finished) {
      go('#/result/' + session.id);
      return;
    }
    renderArena();
    flashDuel();
  }

  function skipPair() {
    if (!state.session || !state.session.current) return;
    stopPreview();
    Engine.skip(state.session);
    Storage.saveSession(state.session);
    renderArena();
    flashDuel();
  }

  /* Replays the swap animation on the freshly rendered pair. Removing the
   * class and forcing a reflow makes it re-trigger every round. */
  function flashDuel() {
    var duel = el('duel');
    duel.classList.remove('swap');
    void duel.offsetWidth;
    duel.classList.add('swap');
  }

  function finishEarly() {
    var session = state.session;
    if (session.history.length < 3) return;
    session.targetRounds = session.history.length;
    session.finished = true;
    session.current = null;
    Storage.saveSession(session);
    go('#/result/' + session.id);
  }

  /* ---------- results ---------- */

  function renderResults() {
    var session = state.session;
    var rows = Engine.standings(session);
    var progress = Engine.progress(session);

    el('resultHead').innerHTML =
      '<span class="head-emoji">' + escapeHtml(session.topicEmoji || '⭐') + '</span>' +
      '<span><h1>Your ' + escapeHtml(session.topicName) + ' ranking</h1>' +
      '<span class="head-sub">' + escapeHtml(session.levelName) + ' · ' +
      plural(rows.length, 'option') + ' · ' + plural(session.history.length, 'comparison') + '</span></span>';

    var winner = rows[0];
    var winnerMedia = Media.get(winner, session.mediaKind);
    el('podium').innerHTML = '<div class="winner">' +
      (winnerMedia ? '<img class="winner-media" data-shape="' + Media.shape(session.mediaKind) + '" src="' + escapeHtml(winnerMedia) + '" alt="">' : '') +
      '<span class="winner-rank">1</span>' +
      '<span class="winner-body">' +
        '<span class="winner-name">' + escapeHtml(winner.name) + '</span>' +
        (winner.meta ? '<span class="winner-meta">' + escapeHtml(winner.meta) + '</span>' : '') +
        '<span class="winner-record">' + winner.wins + ' won · ' + winner.losses + ' lost' +
          (winner.ties ? ' · ' + winner.ties + ' tied' : '') + '</span>' +
      '</span>' +
      '</div>';

    var top = rows[0].rating;
    var bottom = rows[rows.length - 1].rating;
    var span = Math.max(1, top - bottom);

    el('resultTable').innerHTML =
      '<thead><tr><th class="rank">#</th><th>Option</th><th>Strength</th>' +
      '<th class="num">W–L–T</th><th class="num">Win %</th></tr></thead><tbody>' +
      rows.map(function (row) {
        var width = 6 + Math.round(((row.rating - bottom) / span) * 94);
        var flag = row.confidence < 0.5
          ? '<span class="low-conf" title="Seen in only ' + plural(row.played, 'comparison') + '">low data</span>'
          : '';
        var media = Media.get(row, session.mediaKind);
        var page = Media.link(row, session.mediaKind);
        var name = page
          ? '<a href="' + escapeHtml(page) + '" target="_blank" rel="noopener">' + escapeHtml(row.name) + '</a>'
          : escapeHtml(row.name);
        return '<tr>' +
          '<td class="rank">' + row.rank + '</td>' +
          '<td class="name"><div class="name-cell">' +
            (media ? '<img class="thumb" data-shape="' + Media.shape(session.mediaKind) + '" src="' + escapeHtml(media) + '" alt="" loading="lazy">' : '') +
            '<div><b>' + name + '</b>' + flag +
            (row.meta ? '<span class="meta">' + escapeHtml(row.meta) + '</span>' : '') + '</div>' +
          '</div></td>' +
          '<td><div class="bar" style="width:' + width + '%"></div></td>' +
          '<td class="num">' + row.wins + '–' + row.losses + '–' + row.ties + '</td>' +
          '<td class="num">' + Math.round(row.winRate * 100) + '%</td>' +
          '</tr>';
      }).join('') + '</tbody>';

    el('resultNote').textContent = 'Strength comes from a Bradley-Terry fit over all ' +
      session.history.length + ' of your answers, not just win counts — beating a strong ' +
      'option counts for more than beating a weak one. Items marked "low data" were shown ' +
      'too few times to be confident about; refine further to firm them up.';

    el('refineBtn').textContent = progress.rounds >= Engine.maxUsefulRounds(rows.length)
      ? 'Keep going anyway'
      : 'Refine further';
  }

  function shareText() {
    var session = state.session;
    var rows = Engine.standings(session).slice(0, 10);
    return 'My ' + session.topicName + ' ranking (' + session.levelName + ')\n' +
      rows.map(function (row) { return row.rank + '. ' + row.name; }).join('\n');
  }

  function copyResults() {
    var text = shareText();
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        toast('Top 10 copied');
      }, function () { fallbackCopy(text); });
    } else {
      fallbackCopy(text);
    }
  }

  function fallbackCopy(text) {
    var area = document.createElement('textarea');
    area.value = text;
    area.setAttribute('readonly', '');
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try {
      document.execCommand('copy');
      toast('Top 10 copied');
    } catch (err) {
      toast('Copy failed — select the text manually');
    }
    document.body.removeChild(area);
  }

  function downloadCsv() {
    var session = state.session;
    var rows = Engine.standings(session);
    var lines = [['rank', 'name', 'detail', 'strength', 'wins', 'losses', 'ties', 'comparisons'].join(',')];
    rows.forEach(function (row) {
      lines.push([row.rank, csvCell(row.name), csvCell(row.meta), row.score,
        row.wins, row.losses, row.ties, row.played].join(','));
    });
    var blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var link = document.createElement('a');
    link.href = url;
    link.download = Data.slug(session.topicName) + '-ranking.csv';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  function csvCell(value) {
    return '"' + String(value || '').replace(/"/g, '""') + '"';
  }

  /* ---------- custom topics ---------- */

  function openTopicModal() {
    el('topicName').value = '';
    el('topicEmoji').value = '';
    el('topicItems').value = '';
    el('topicError').hidden = true;
    el('topicModal').hidden = false;
    el('topicName').focus();
  }

  function saveCustomTopic() {
    var name = el('topicName').value.trim();
    var lines = el('topicItems').value.split('\n');
    var error = el('topicError');

    if (!name) {
      error.textContent = 'Give the topic a name.';
      error.hidden = false;
      return;
    }
    var topic = Data.makeCustomTopic(name, el('topicEmoji').value.trim() || '⭐', lines);
    if (topic.items.length < 4) {
      error.textContent = 'Add at least four options — ranking needs something to compare.';
      error.hidden = false;
      return;
    }
    Storage.saveTopic(topic);
    el('topicModal').hidden = true;
    toast('Topic created');
    go('#/topic/' + topic.id);
  }

  /* ---------- routing ---------- */

  function show(screen) {
    ['home', 'level', 'arena', 'results'].forEach(function (name) {
      el('screen-' + name).hidden = name !== screen;
    });
    el('backBtn').hidden = screen === 'home';
    window.scrollTo(0, 0);
  }

  /* The pair on screen goes to the front of the queue, so what the user is
   * looking at fills in before the rest of the pool. */
  function prefetchMedia(session) {
    var current = session.current || [];
    var rest = session.order.filter(function (id) { return current.indexOf(id) === -1; });
    Media.prefetch(current.concat(rest).map(function (id) { return session.items[id]; }), session.mediaKind);
  }

  function render() {
    stopPreview();
    var route = (location.hash || '#/').replace(/^#/, '');
    var parts = route.split('/').filter(Boolean);

    if (parts[0] === 'topic' && parts[1]) {
      var topic = findTopic(parts[1]);
      if (!topic) return go('#/');
      state.topic = topic;
      var saved = Storage.prefs();
      if (saved.level) state.level = Data.getLevel(saved.level);
      if (saved.mode) state.mode = saved.mode;
      show('level');
      renderLevel();
      return;
    }

    if ((parts[0] === 'play' || parts[0] === 'result') && parts[1]) {
      var session = Storage.getSession(parts[1]);
      if (!session) return go('#/');
      state.session = session;
      prefetchMedia(session);
      if (parts[0] === 'play') {
        if (session.finished) return go('#/result/' + session.id);
        show('arena');
        renderArena();
      } else {
        show('results');
        renderResults();
      }
      return;
    }

    show('home');
    renderHome();
  }

  /* ---------- wiring ---------- */

  function onClick(event) {
    var target = event.target.closest('[data-topic],[data-level],[data-mode],[data-go]');
    if (!target) return;
    if (target.dataset.topic) return go('#/topic/' + target.dataset.topic);
    if (target.dataset.go) return go(target.dataset.go);
    if (target.dataset.level) {
      state.level = Data.getLevel(target.dataset.level);
      renderLevel();
      return;
    }
    if (target.dataset.mode) {
      state.mode = target.dataset.mode;
      renderLevel();
    }
  }

  function onKeydown(event) {
    if (el('screen-arena').hidden) {
      if (event.key === 'Escape' && !el('topicModal').hidden) el('topicModal').hidden = true;
      return;
    }
    if (event.target.tagName === 'INPUT' || event.target.tagName === 'TEXTAREA') return;
    /* Holding a key down should not blast through rounds. */
    if (event.repeat) return;

    var play = event.target.closest && event.target.closest('.play');
    if (play && (event.key === 'Enter' || event.key === ' ')) {
      event.preventDefault();
      togglePreview(play);
      return;
    }

    if (event.key === 'ArrowLeft' || event.key === '1') {
      event.preventDefault();
      choose(el('optionA').dataset.id);
    } else if (event.key === 'ArrowRight' || event.key === '2') {
      event.preventDefault();
      choose(el('optionB').dataset.id);
    } else if (event.key === ' ') {
      event.preventDefault();
      choose(null);
    } else if (event.key === 's') {
      event.preventDefault();
      skipPair();
    } else if (event.key === 'u') {
      undoRound();
    }
  }

  function undoRound() {
    if (!state.session || !state.session.history.length) return;
    stopPreview();
    Engine.undo(state.session);
    Storage.saveSession(state.session);
    renderArena();
  }

  function init() {
    document.addEventListener('click', onClick);
    document.addEventListener('keydown', onKeydown);
    window.addEventListener('hashchange', render);
    Media.onChange(function () {
      if (!state.session) return;
      if (!el('screen-arena').hidden) refreshArenaMedia();
      else if (!el('screen-results').hidden) renderResults();
    });

    el('backBtn').addEventListener('click', function () {
      if (history.length > 1) history.back();
      else go('#/');
    });
    el('newTopicBtn').addEventListener('click', openTopicModal);
    el('cancelTopicBtn').addEventListener('click', function () { el('topicModal').hidden = true; });
    el('saveTopicBtn').addEventListener('click', saveCustomTopic);
    el('topicModal').addEventListener('click', function (event) {
      if (event.target === el('topicModal')) el('topicModal').hidden = true;
    });

    el('startBtn').addEventListener('click', startSession);
    el('optionA').addEventListener('click', onOptionClick);
    el('optionB').addEventListener('click', onOptionClick);
    el('tieBtn').addEventListener('click', function () { choose(null); });
    el('skipBtn').addEventListener('click', skipPair);
    el('undoBtn').addEventListener('click', undoRound);
    el('finishBtn').addEventListener('click', finishEarly);

    el('refineBtn').addEventListener('click', function () {
      var extra = Math.max(8, Math.round(state.session.order.length * 0.75));
      Engine.extend(state.session, extra);
      Storage.saveSession(state.session);
      go('#/play/' + state.session.id);
    });
    el('copyBtn').addEventListener('click', copyResults);
    el('csvBtn').addEventListener('click', downloadCsv);
    el('againBtn').addEventListener('click', function () {
      var topic = findTopic(state.session.topicId);
      if (!topic) return go('#/');
      state.topic = topic;
      state.level = Data.getLevel(state.session.levelId);
      state.mode = state.session.mode;
      startSession();
    });
    el('deleteBtn').addEventListener('click', function () {
      Storage.deleteSession(state.session.id);
      toast('Ranking deleted');
      go('#/');
    });

    render();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();
