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

  function hash(text) {
    var h = 0;
    for (var i = 0; i < text.length; i++) h = (h * 31 + text.charCodeAt(i)) | 0;
    return Math.abs(h);
  }

  /* A stable colour and monogram per name, so options stay recognisable
   * without shipping any images. */
  function avatar(name) {
    var seed = hash(name);
    var hue = seed % 360;
    var initials = name.split(/\s+/).slice(0, 2).map(function (word) {
      return word.charAt(0);
    }).join('').toUpperCase();
    return {
      style: 'background: linear-gradient(140deg, hsl(' + hue + ' 70% 62%), hsl(' + ((hue + 48) % 360) + ' 72% 52%));',
      initials: initials || '?'
    };
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

    /* In king of the hill the champion holds its slot, so flag which card is
     * the one staying put. renderOption resets className, so this comes after. */
    if (session.mode === 'gauntlet' && session.champion) {
      [el('optionA'), el('optionB')].forEach(function (node) {
        if (node.dataset.id === session.champion) node.classList.add('is-champion');
      });
    }

    el('undoBtn').disabled = session.history.length === 0;
    el('finishBtn').disabled = session.history.length < 3;

    var top = Engine.standings(session).slice(0, 5);
    el('peekList').innerHTML = top.map(function (row) {
      return '<li><b>' + escapeHtml(row.name) + '</b> · ' + row.wins + 'W ' + row.losses + 'L</li>';
    }).join('') || '<li>No comparisons yet.</li>';
  }

  function renderOption(node, item, key) {
    var art = avatar(item.name);
    node.className = 'option';
    node.dataset.id = item.id;
    node.innerHTML =
      '<span class="option-key">' + key + '</span>' +
      '<span class="option-avatar" style="' + art.style + '">' + escapeHtml(art.initials) + '</span>' +
      '<span class="option-name">' + escapeHtml(item.name) + '</span>' +
      (item.meta ? '<span class="option-meta">' + escapeHtml(item.meta) + '</span>' : '');
  }

  /* Answers are applied synchronously. An earlier version held a lock while a
   * short "you picked this" animation played, which silently swallowed any tap
   * or keypress landing inside that window — the worst possible failure for a
   * ranking app, because the answer looks accepted. Feedback is now purely
   * visual: the incoming pair animates in and nothing gates the input. */
  function choose(winnerId) {
    var session = state.session;
    if (!session || !session.current) return;

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

    var medals = ['🥇', '🥈', '🥉'];
    el('podium').innerHTML = rows.slice(0, 3).map(function (row, index) {
      return '<div class="podium-card p' + (index + 1) + '">' +
        '<div class="podium-medal">' + medals[index] + '</div>' +
        '<div class="podium-name">' + escapeHtml(row.name) + '</div>' +
        (row.meta ? '<div class="podium-meta">' + escapeHtml(row.meta) + '</div>' : '') +
        '<div class="podium-score">' + row.wins + 'W · ' + row.losses + 'L</div>' +
        '</div>';
    }).join('');

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
        return '<tr>' +
          '<td class="rank">' + row.rank + '</td>' +
          '<td class="name"><b>' + escapeHtml(row.name) + '</b>' + flag +
            (row.meta ? '<span>' + escapeHtml(row.meta) + '</span>' : '') + '</td>' +
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

  function render() {
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
    Engine.undo(state.session);
    Storage.saveSession(state.session);
    renderArena();
  }

  function init() {
    document.addEventListener('click', onClick);
    document.addEventListener('keydown', onKeydown);
    window.addEventListener('hashchange', render);

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
    el('optionA').addEventListener('click', function () { choose(this.dataset.id); });
    el('optionB').addEventListener('click', function () { choose(this.dataset.id); });
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
