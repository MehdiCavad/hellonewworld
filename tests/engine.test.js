/* Plain-node tests: node tests/engine.test.js */
var assert = require('assert');
var path = require('path');
var Engine = require(path.join(__dirname, '..', 'assets', 'js', 'engine.js'));
var Data = require(path.join(__dirname, '..', 'assets', 'js', 'data.js'));

var passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log('  ok  ' + name);
}

function makeItems(n) {
  var items = [];
  for (var i = 0; i < n; i++) items.push({ id: 'i' + i, name: 'Item ' + i, meta: '' });
  return items;
}

function newSession(n, overrides) {
  var opts = {
    topicId: 't', topicName: 'Test', levelId: 'standard', levelName: 'Standard',
    items: makeItems(n), targetRounds: 30, seed: 42
  };
  Object.keys(overrides || {}).forEach(function (k) { opts[k] = overrides[k]; });
  return Engine.createSession(opts);
}

test('a new session opens with a valid distinct pair', function () {
  var s = newSession(8);
  assert.ok(s.current, 'expected an opening pair');
  assert.notStrictEqual(s.current[0], s.current[1]);
  assert.ok(s.order.indexOf(s.current[0]) !== -1);
});

test('createSession rejects pools smaller than two', function () {
  assert.throws(function () { newSession(1); });
});

test('the winner climbs and the loser drops symmetrically', function () {
  var s = newSession(8);
  var a = s.current[0], b = s.current[1];
  Engine.submit(s, a);
  assert.ok(s.items[a].rating > Engine.BASE_RATING, 'winner should climb');
  assert.ok(s.items[b].rating < Engine.BASE_RATING, 'loser should drop');
  var gain = s.items[a].rating - Engine.BASE_RATING;
  var loss = Engine.BASE_RATING - s.items[b].rating;
  assert.ok(Math.abs(gain - loss) < 1e-6, 'one result should move both sides equally');
  assert.strictEqual(s.items[a].wins, 1);
  assert.strictEqual(s.items[b].losses, 1);
  s.order.forEach(function (id) {
    if (id !== a && id !== b) {
      assert.ok(Math.abs(s.items[id].rating - Engine.BASE_RATING) < 1e-6,
        'untouched items keep the base rating');
    }
  });
});

test('rating differences predict outcomes through the Bradley-Terry model', function () {
  var s = newSession(4, { targetRounds: 99 });
  var a = s.current[0], b = s.current[1];
  for (var i = 0; i < 5; i++) {
    s.current = [a, b];
    Engine.submit(s, a);
  }
  var p = Engine.winProbability(s.items[a].rating, s.items[b].rating);
  assert.ok(p > 0.8, 'five straight wins should imply a strong favourite, got ' + p.toFixed(2));
  assert.ok(Math.abs(p + Engine.winProbability(s.items[b].rating, s.items[a].rating) - 1) < 1e-9);
});

test('a tie leaves two equal ratings untouched and counts for both', function () {
  var s = newSession(8);
  var a = s.current[0], b = s.current[1];
  Engine.submit(s, null);
  assert.ok(Math.abs(s.items[a].rating - Engine.BASE_RATING) < 1e-6);
  assert.ok(Math.abs(s.items[b].rating - Engine.BASE_RATING) < 1e-6);
  assert.strictEqual(s.items[a].ties, 1);
  assert.strictEqual(s.items[b].ties, 1);
});

test('submit rejects a winner that is not on screen', function () {
  var s = newSession(8);
  assert.throws(function () { Engine.submit(s, 'not-in-pool'); });
});

test('undo restores ratings, counters and the pair exactly', function () {
  var s = newSession(8);
  Engine.submit(s, s.current[1]);
  Engine.submit(s, null);
  var before = JSON.stringify(s.items);
  var a = s.current[0], b = s.current[1];
  Engine.submit(s, a);
  Engine.undo(s);
  assert.strictEqual(JSON.stringify(s.items), before, 'items must return to their prior state');
  assert.strictEqual(s.history.length, 2);
  assert.deepStrictEqual(s.current, [a, b], 'the undone pair is shown again');
});

test('undo on an empty history is a no-op', function () {
  var s = newSession(8);
  Engine.undo(s);
  assert.strictEqual(s.history.length, 0);
  assert.ok(s.current);
});

test('the session finishes exactly at the target round count', function () {
  var s = newSession(6, { targetRounds: 10 });
  for (var i = 0; i < 10; i++) {
    assert.ok(s.current, 'expected a pair at round ' + i);
    Engine.submit(s, s.current[0]);
  }
  assert.strictEqual(s.finished, true);
  assert.strictEqual(s.current, null);
  assert.strictEqual(s.history.length, 10);
});

test('extend reopens a finished session', function () {
  var s = newSession(6, { targetRounds: 4 });
  for (var i = 0; i < 4; i++) Engine.submit(s, s.current[0]);
  Engine.extend(s, 5);
  assert.strictEqual(s.finished, false);
  assert.ok(s.current);
  assert.strictEqual(s.targetRounds, 9);
});

test('smart pairing covers every item before repeating anyone', function () {
  var n = 12;
  var s = newSession(n, { targetRounds: 100 });
  for (var i = 0; i < n / 2; i++) Engine.submit(s, s.current[0]);
  s.order.forEach(function (id) {
    assert.strictEqual(s.items[id].played, 1, id + ' should have been seen once');
  });
});

test('gauntlet mode keeps the winner on screen', function () {
  var s = newSession(10, { mode: 'gauntlet', targetRounds: 20 });
  for (var i = 0; i < 8; i++) {
    var winner = s.current[0];
    Engine.submit(s, winner);
    assert.ok(s.current.indexOf(winner) !== -1, 'champion should face the next challenger');
  }
});

test('king of the hill freezes the champion on the side it already holds', function () {
  var s = newSession(10, { mode: 'gauntlet', targetRounds: 30 });
  /* Win from the left, then from whichever slot the champion is parked in. */
  var champion = s.current[0];
  var side = 0;
  Engine.submit(s, champion);
  for (var i = 0; i < 12; i++) {
    assert.strictEqual(s.current[side], champion,
      'round ' + i + ': champion should still hold slot ' + side);
    assert.notStrictEqual(s.current[1 - side], champion, 'champion must not fill both slots');
    Engine.submit(s, champion);          // champion keeps winning, keeps its seat
  }
  /* When the challenger wins it takes over that same seat. */
  var challenger = s.current[1 - side];
  Engine.submit(s, challenger);
  assert.strictEqual(s.current[1 - side], challenger,
    'a new champion holds the slot it won from');
});

test('undo restores the exact left/right layout of the previous pair', function () {
  var s = newSession(10, { mode: 'gauntlet', targetRounds: 30 });
  Engine.submit(s, s.current[0]);
  var pair = s.current.slice();
  Engine.submit(s, s.current[1]);
  Engine.undo(s);
  assert.deepStrictEqual(s.current, pair, 'sides must come back in the same order');
});

test('smart duels still vary which side an item appears on', function () {
  var s = newSession(12, { targetRounds: 80 });
  var sides = {};
  for (var i = 0; i < 60 && s.current; i++) {
    s.current.forEach(function (id, index) {
      (sides[id] = sides[id] || {})[index] = true;
    });
    Engine.submit(s, s.current[0]);
  }
  var bothSides = Object.keys(sides).filter(function (id) {
    return sides[id][0] && sides[id][1];
  });
  assert.ok(bothSides.length >= 8,
    'most items should be seen on both sides, got ' + bothSides.length);
});

test('skip swaps the pair without recording a result', function () {
  var s = newSession(10);
  var first = s.current.slice();
  Engine.skip(s);
  assert.strictEqual(s.history.length, 0);
  assert.notStrictEqual(first.join('|'), s.current.join('|'));
});

test('a session survives a JSON round trip', function () {
  var s = newSession(8);
  Engine.submit(s, s.current[0]);
  var restored = JSON.parse(JSON.stringify(s));
  Engine.submit(restored, restored.current[0]);
  assert.strictEqual(restored.history.length, 2);
});

/* Convergence: give every item a hidden true strength, let a noisy oracle
 * answer, and check the produced order matches the truth. */
function simulate(n, rounds, mode, seed, noise) {
  var truth = {};
  var items = [];
  for (var i = 0; i < n; i++) {
    items.push({ id: 'i' + i, name: 'Item ' + i, meta: '' });
    truth['i' + i] = i; // i0 is weakest, i(n-1) strongest
  }
  var s = Engine.createSession({
    topicId: 't', topicName: 'Sim', levelId: 'x', levelName: 'X',
    items: items, targetRounds: rounds, seed: seed, mode: mode
  });
  var rng = Engine.makeRng(seed + 1);
  while (!s.finished && s.current) {
    var a = s.current[0], b = s.current[1];
    var better = truth[a] > truth[b] ? a : b;
    var worse = better === a ? b : a;
    Engine.submit(s, rng() < (noise || 0) ? worse : better);
  }
  var ranked = Engine.standings(s);
  /* Mean absolute rank error against the true order. */
  var error = 0;
  ranked.forEach(function (row, index) {
    var trueRank = n - truth[row.id]; // strongest -> rank 1
    error += Math.abs(trueRank - (index + 1));
  });
  return { session: s, ranked: ranked, meanRankError: error / n };
}

test('a clean oracle recovers the exact order at the default depth', function () {
  var out = simulate(16, Data.maxUsefulRounds(16), 'smart', 7, 0);
  assert.strictEqual(out.meanRankError, 0, 'expected a perfect ranking, got error ' + out.meanRankError);
  assert.strictEqual(out.ranked[0].id, 'i15');
  assert.strictEqual(out.ranked[15].id, 'i0');
});

test('smart pairing stays accurate with 10% contradictory answers', function () {
  var total = 0;
  for (var seed = 1; seed <= 8; seed++) {
    total += simulate(16, Data.maxUsefulRounds(16), 'smart', seed, 0.1).meanRankError;
  }
  var avg = total / 8;
  assert.ok(avg < 1.2, 'mean rank error should stay under 1.2, got ' + avg.toFixed(2));
});

test('smart pairing beats gauntlet at the same round budget', function () {
  var smart = 0, gauntlet = 0;
  for (var seed = 1; seed <= 8; seed++) {
    smart += simulate(16, 34, 'smart', seed, 0.05).meanRankError;
    gauntlet += simulate(16, 34, 'gauntlet', seed, 0.05).meanRankError;
  }
  assert.ok(smart < gauntlet, 'smart ' + (smart / 8).toFixed(2) + ' should beat gauntlet ' + (gauntlet / 8).toFixed(2));
});

test('progress reports rounds, target and coverage', function () {
  var s = newSession(8, { targetRounds: 20 });
  for (var i = 0; i < 8; i++) Engine.submit(s, s.current[0]);
  var p = Engine.progress(s);
  assert.strictEqual(p.rounds, 8);
  assert.strictEqual(p.target, 20);
  assert.strictEqual(p.remaining, 12);
  assert.ok(p.ratio > 0.39 && p.ratio < 0.41);
  assert.ok(p.leastSeen >= 1);
});

test('standings rank by rating and expose a per-item confidence', function () {
  var out = simulate(10, 40, 'smart', 3, 0);
  var rows = out.ranked;
  for (var i = 1; i < rows.length; i++) {
    assert.ok(rows[i - 1].rating >= rows[i].rating, 'rows must be sorted by rating');
    assert.strictEqual(rows[i].rank, i + 1);
    assert.ok(rows[i].confidence > 0 && rows[i].confidence <= 1);
  }
});

/* Data layer */
test('every seeded topic has enough items for every level', function () {
  Data.topics.forEach(function (topic) {
    Data.levels.forEach(function (level) {
      var pool = Data.buildPool(topic, level, Engine.makeRng(5));
      assert.ok(pool.length >= 2, topic.name + '/' + level.name + ' pool too small');
      if (level.size > 0) {
        assert.strictEqual(pool.length, Math.min(level.size, pool.length));
        assert.ok(pool.length === Data.countForLevel(topic, level));
      }
      var ids = {};
      pool.forEach(function (item) {
        assert.ok(!ids[item.id], 'duplicate item id ' + item.id);
        ids[item.id] = true;
        assert.ok(level.tiers.indexOf(item.tier) !== -1, 'item leaked from a locked tier');
      });
    });
  });
});

test('casual level only serves tier-one items', function () {
  var topic = Data.getTopic('movies');
  var pool = Data.buildPool(topic, Data.getLevel('casual'), Engine.makeRng(9));
  assert.strictEqual(pool.length, 8);
  pool.forEach(function (item) { assert.strictEqual(item.tier, 1); });
});

test('marathon uses the whole topic and sizes its own round count', function () {
  var topic = Data.getTopic('movies');
  var level = Data.getLevel('marathon');
  var pool = Data.buildPool(topic, level, Engine.makeRng(9));
  assert.strictEqual(pool.length, topic.items.length);
  assert.strictEqual(Data.roundsFor(level, pool.length), Data.maxUsefulRounds(pool.length));
});

test('custom topics parse names, optional meta and blank lines', function () {
  var topic = Data.makeCustomTopic('My List', '🍀', ['Alpha|first', '', '  Beta  ', 'Gamma']);
  assert.strictEqual(topic.items.length, 3);
  assert.strictEqual(topic.items[0].name, 'Alpha');
  assert.strictEqual(topic.items[0].meta, 'first');
  assert.strictEqual(topic.items[1].name, 'Beta');
  assert.strictEqual(topic.builtIn, false);
});


/* Media lookup — the pure parts; the network is exercised in the browser. */
var Media = require(path.join(__dirname, '..', 'assets', 'js', 'media.js'));

test('media looks items up by their wiki title when one is set', function () {
  assert.strictEqual(Media.titleOf({ name: 'Parasite', wiki: 'Parasite (2019 film)' }), 'Parasite (2019 film)');
  assert.strictEqual(Media.titleOf({ name: 'Lionel Messi', wiki: '' }), 'Lionel Messi');
});

test('media only accepts Commons-hosted images', function () {
  assert.ok(Media.isFree('https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/X.jpg/640px-X.jpg'));
  assert.ok(!Media.isFree('https://upload.wikimedia.org/wikipedia/en/thumb/1/1c/Poster.jpg/640px-Poster.jpg'),
    'a poster kept locally on en.wikipedia is usually non-free');
});

test('media request batches titles into one CORS-enabled API call', function () {
  var url = Media.requestUrl(['Lionel Messi', 'Pelé']);
  assert.ok(url.indexOf('https://en.wikipedia.org/w/api.php?') === 0);
  assert.ok(url.indexOf('origin=*') !== -1, 'origin=* is what makes the API answer cross-origin');
  assert.ok(url.indexOf('redirects=1') !== -1);
  assert.ok(url.indexOf('titles=' + encodeURIComponent('Lionel Messi|Pelé')) !== -1);
});

test('media follows normalisation and redirects back to the requested title', function () {
  var json = { query: {
    normalized: [{ from: 'xavi', to: 'Xavi' }],
    redirects: [{ from: 'Xavi', to: 'Xavi (footballer)' }],
    pages: [
      { title: 'Xavi (footballer)', thumbnail: { source: 'https://upload.wikimedia.org/wikipedia/commons/x/xa/Xavi.jpg' } },
      { title: 'Parasite (2019 film)', thumbnail: { source: 'https://upload.wikimedia.org/wikipedia/en/p/pa/Poster.jpg' } },
      { title: 'Nobody Here', missing: true }
    ]
  } };
  var out = Media.parseResponse(json, ['xavi', 'Parasite (2019 film)', 'Nobody Here']);
  assert.strictEqual(out['xavi'].url, 'https://upload.wikimedia.org/wikipedia/commons/x/xa/Xavi.jpg');
  assert.strictEqual(out['xavi'].page, 'Xavi (footballer)', 'attribution points at the final article');
  assert.strictEqual(out['Parasite (2019 film)'].url, null, 'non-free poster is dropped');
  assert.strictEqual(out['Parasite (2019 film)'].page, 'Parasite (2019 film)', 'but the article link stays');
  assert.strictEqual(out['Nobody Here'].url, null);
  assert.strictEqual(out['Nobody Here'].page, null);
});

test('media get() is cache-only and honours the 30-day expiry', function () {
  Media._reset();
  var store = {};
  global.Storage = {
    mediaCache: function () { return store; },
    saveMediaCache: function (c) { store = c; }
  };
  store['Fresh'] = { url: 'https://upload.wikimedia.org/wikipedia/commons/f/f1/F.jpg', page: 'Fresh', ts: Date.now() };
  store['Stale'] = { url: 'https://upload.wikimedia.org/wikipedia/commons/s/s1/S.jpg', page: 'Stale', ts: Date.now() - 31 * 86400000 };
  assert.strictEqual(Media.get({ name: 'Fresh' }), store['Fresh'].url);
  assert.strictEqual(Media.get({ name: 'Stale' }), null, 'expired entries are treated as absent');
  assert.strictEqual(Media.get({ name: 'Unknown' }), null);
  assert.strictEqual(Media.pageUrl({ name: 'Fresh' }), 'https://en.wikipedia.org/wiki/Fresh');
  assert.strictEqual(Media.prefetch([{ name: 'Fresh' }]), 0, 'without fetch() prefetch is a no-op');
  delete global.Storage;
  Media._reset();
});

test('sessions carry the wiki title so a resumed session can still find images', function () {
  var s = Engine.createSession({
    topicId: 't', topicName: 'T', levelId: 'x', levelName: 'X', targetRounds: 5,
    items: [{ id: 'a', name: 'Parasite', wiki: 'Parasite (2019 film)' }, { id: 'b', name: 'Pelé' }]
  });
  assert.strictEqual(s.items.a.wiki, 'Parasite (2019 film)');
  assert.strictEqual(s.items.b.wiki, '');
  /* The results screen reads standings rows, not session items, so the title
   * has to survive that hop too or half the table silently loses its images. */
  var rows = Engine.standings(s);
  var parasite = rows.filter(function (r) { return r.id === 'a'; })[0];
  assert.strictEqual(parasite.wiki, 'Parasite (2019 film)');
});

console.log('\n' + passed + ' tests passed (incl. media)');
