/* Pairwise ranking engine.
 *
 * A session holds a pool of items. Every round the engine hands the UI two of
 * them; the UI reports a winner (or a tie) and the round is appended to the
 * history. The history is the only source of truth — ratings are re-derived
 * from it, which is what makes undo exact and makes a session safe to store
 * as plain JSON and resume anywhere.
 *
 * Ratings come from a Bradley-Terry fit: each item gets a strength p, and the
 * model says item i beats j with probability p_i / (p_i + p_j). Fitting all
 * strengths at once uses every comparison to place every item, so it needs far
 * fewer rounds than an online scheme like Elo, where an early loss to a weak
 * opponent never fully washes out. Strengths are found with Hunter's MM
 * iteration, regularised by a half-win/half-loss against a virtual average
 * opponent so undefeated and winless items still get a finite rating.
 *
 * Pairing strategies:
 *   smart    - scores every possible pair and serves the most informative
 *              one: close in rating, not asked before, and covering items the
 *              session has seen least.
 *   gauntlet - the winner stays on and faces a fresh challenger
 *              (king of the hill). Fun, but weaker at ordering the tail.
 */
(function (global) {
  'use strict';

  var BASE_RATING = 1500;
  var RATING_SCALE = 400;
  var PRIOR = 0.5;        // pseudo win + pseudo loss against a virtual average
  var MAX_ITERATIONS = 400;
  var TOLERANCE = 1e-10;

  /* Deterministic PRNG so a session can be replayed and tests are stable. */
  function makeRng(seed) {
    var t = (seed >>> 0) || 1;
    return function () {
      t += 0x6D2B79F5;
      var r = t;
      r = Math.imul(r ^ (r >>> 15), r | 1);
      r ^= r + Math.imul(r ^ (r >>> 7), r | 61);
      return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
  }

  function pairKey(a, b) {
    return a < b ? a + '|' + b : b + '|' + a;
  }

  /* Probability that a beats b, given their ratings. */
  function winProbability(ratingA, ratingB) {
    return 1 / (1 + Math.pow(10, (ratingB - ratingA) / RATING_SCALE));
  }

  function createSession(options) {
    var pool = options.items;
    if (!pool || pool.length < 2) throw new Error('A session needs at least 2 items');

    var items = {};
    var order = [];
    pool.forEach(function (item) {
      items[item.id] = {
        id: item.id,
        name: item.name,
        meta: item.meta || '',
        rating: BASE_RATING,
        played: 0,
        wins: 0,
        losses: 0,
        ties: 0
      };
      order.push(item.id);
    });

    var session = {
      id: options.id || ('s' + Date.now().toString(36) + Math.floor(Math.random() * 1e4).toString(36)),
      topicId: options.topicId,
      topicName: options.topicName,
      topicEmoji: options.topicEmoji || '⭐',
      levelId: options.levelId,
      levelName: options.levelName,
      mode: options.mode === 'gauntlet' ? 'gauntlet' : 'smart',
      targetRounds: options.targetRounds || 0,
      seed: options.seed || Math.floor(Math.random() * 1e9),
      createdAt: options.createdAt || Date.now(),
      updatedAt: Date.now(),
      items: items,
      order: order,
      history: [],
      pairSeen: {},
      champion: null,
      current: null,
      finished: false
    };
    session.current = nextPair(session);
    return session;
  }

  /* ---- Rating model ---------------------------------------------------- */

  /* Re-derives every rating from the comparison history. */
  function refit(session) {
    var ids = session.order;
    var n = ids.length;
    var index = {};
    var i, j;
    for (i = 0; i < n; i++) index[ids[i]] = i;

    var wins = new Float64Array(n);
    var counts = [];
    for (i = 0; i < n; i++) counts.push(new Float64Array(n));

    session.history.forEach(function (round) {
      var a = index[round.a];
      var b = index[round.b];
      if (a === undefined || b === undefined) return;
      counts[a][b] += 1;
      counts[b][a] += 1;
      if (round.winner === null) {
        wins[a] += 0.5;
        wins[b] += 0.5;
      } else if (round.winner === round.a) {
        wins[a] += 1;
      } else {
        wins[b] += 1;
      }
    });

    var strength = new Float64Array(n);
    for (i = 0; i < n; i++) strength[i] = 1;

    for (var iter = 0; iter < MAX_ITERATIONS; iter++) {
      var maxDelta = 0;
      for (i = 0; i < n; i++) {
        /* MM update: p_i <- W_i / sum_j n_ij / (p_i + p_j), with the prior
         * contributing PRIOR wins and 2*PRIOR games against strength 1. */
        var denominator = (2 * PRIOR) / (strength[i] + 1);
        for (j = 0; j < n; j++) {
          if (j !== i && counts[i][j]) {
            denominator += counts[i][j] / (strength[i] + strength[j]);
          }
        }
        var next = (wins[i] + PRIOR) / denominator;
        maxDelta = Math.max(maxDelta, Math.abs(next - strength[i]) / (strength[i] || 1));
        strength[i] = next;
      }

      /* Only ratios are identified, so renormalise to a geometric mean of 1
       * to keep the numbers stable and the scale comparable across sessions. */
      var logSum = 0;
      for (i = 0; i < n; i++) logSum += Math.log(strength[i]);
      var scale = Math.exp(logSum / n);
      for (i = 0; i < n; i++) strength[i] /= scale;

      if (maxDelta < TOLERANCE) break;
    }

    for (i = 0; i < n; i++) {
      session.items[ids[i]].rating = BASE_RATING + RATING_SCALE * (Math.log(strength[i]) / Math.LN10);
    }
    return session;
  }

  /* ---- Pairing --------------------------------------------------------- */

  /* Re-seeded from the round number so a restored session keeps producing the
   * same stream it would have produced without a reload. */
  function rngFor(session) {
    return makeRng(session.seed + session.history.length * 7919 + session.skips * 104729);
  }

  /* Scores every candidate pair and serves the most useful one. Scanning all
   * pairs rather than picking one side first measurably improves the final
   * order: it can always reach for the closest pair that has not met yet,
   * which is precisely the comparison the ranking is still unsure about. */
  function nextPair(session) {
    if (typeof session.skips !== 'number') session.skips = 0;
    var ids = session.order;
    if (ids.length < 2) return null;
    var random = rngFor(session);
    var items = session.items;
    var lastKey = session.current ? pairKey(session.current[0], session.current[1]) : null;

    var minPlayed = Infinity;
    ids.forEach(function (id) { minPlayed = Math.min(minPlayed, items[id].played); });

    /* Gauntlet keeps the reigning winner on screen, so only pairs containing
     * the champion are eligible. */
    var champion = (session.mode === 'gauntlet' && session.champion && items[session.champion])
      ? session.champion
      : null;

    var pairs = [];
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        var a = items[ids[i]];
        var b = items[ids[j]];
        if (champion && a.id !== champion && b.id !== champion) continue;
        var key = pairKey(a.id, b.id);
        var seen = session.pairSeen[key] || 0;
        /* Lower cost is a better next question: close in rating (so the answer
         * is informative), not asked before, and involving items the session
         * has not already over-sampled. */
        var cost = Math.abs(a.rating - b.rating)
          + seen * 500
          + (a.played - minPlayed) * 70
          + (b.played - minPlayed) * 70;
        if (lastKey && key === lastKey) cost += 10000;
        pairs.push({ a: a.id, b: b.id, cost: cost });
      }
    }
    if (!pairs.length) return null;

    pairs.sort(function (x, y) { return x.cost - y.cost; });
    /* Randomise only between near-equally good pairs. A flat top-N would let
     * an already well-covered pair beat an unseen one and leave part of the
     * pool unranked. */
    var best = pairs[0].cost;
    var shortlist = pairs.filter(function (p) { return p.cost <= best + 40; }).slice(0, 3);
    var chosen = shortlist[Math.floor(random() * shortlist.length)];

    /* King of the hill: the reigning pick holds the slot it already occupies,
     * so it visibly stays put and only the challenger swaps in. That trades
     * away side randomisation for the champion, which is the point of the
     * mode — smart duels below keep it. */
    if (champion) {
      var challenger = chosen.a === champion ? chosen.b : chosen.a;
      var heldSide = session.current ? session.current.indexOf(champion) : -1;
      return heldSide === 1 ? [challenger, champion] : [champion, challenger];
    }

    /* Randomise which side each item shows on, so position bias does not
     * quietly become part of the ranking. */
    return random() < 0.5 ? [chosen.a, chosen.b] : [chosen.b, chosen.a];
  }

  /* ---- Mutations ------------------------------------------------------- */

  /* Records one comparison. `winnerId` may be null for "too close to call". */
  function submit(session, winnerId) {
    if (!session.current) return session;
    var a = session.current[0];
    var b = session.current[1];
    if (winnerId !== null && winnerId !== a && winnerId !== b) {
      throw new Error('Winner must be one of the two shown items');
    }

    var itemA = session.items[a];
    var itemB = session.items[b];

    session.history.push({
      a: a,
      b: b,
      winner: winnerId,
      prevChampion: session.champion,
      ts: Date.now()
    });

    itemA.played += 1;
    itemB.played += 1;
    if (winnerId === null) {
      itemA.ties += 1;
      itemB.ties += 1;
    } else if (winnerId === a) {
      itemA.wins += 1;
      itemB.losses += 1;
    } else {
      itemB.wins += 1;
      itemA.losses += 1;
    }

    var key = pairKey(a, b);
    session.pairSeen[key] = (session.pairSeen[key] || 0) + 1;
    session.champion = winnerId || session.champion;
    session.updatedAt = Date.now();
    refit(session);

    if (session.targetRounds > 0 && session.history.length >= session.targetRounds) {
      session.finished = true;
      session.current = null;
    } else {
      session.current = nextPair(session);
    }
    return session;
  }

  /* Replaces the current pair without recording a result. */
  function skip(session) {
    if (!session.current) return session;
    var key = pairKey(session.current[0], session.current[1]);
    /* Mark it seen so the same duel is not offered straight back. */
    session.pairSeen[key] = (session.pairSeen[key] || 0) + 1;
    session.skips = (session.skips || 0) + 1;
    session.current = nextPair(session);
    session.updatedAt = Date.now();
    return session;
  }

  function undo(session) {
    var last = session.history.pop();
    if (!last) return session;

    var itemA = session.items[last.a];
    var itemB = session.items[last.b];
    itemA.played -= 1;
    itemB.played -= 1;
    if (last.winner === null) {
      itemA.ties -= 1;
      itemB.ties -= 1;
    } else if (last.winner === last.a) {
      itemA.wins -= 1;
      itemB.losses -= 1;
    } else {
      itemB.wins -= 1;
      itemA.losses -= 1;
    }

    var key = pairKey(last.a, last.b);
    session.pairSeen[key] = Math.max(0, (session.pairSeen[key] || 1) - 1);
    session.champion = last.prevChampion;
    session.finished = false;
    session.current = [last.a, last.b];
    session.updatedAt = Date.now();
    refit(session);
    return session;
  }

  /* Extends a finished session so the user can keep refining the order. */
  function extend(session, extraRounds) {
    session.targetRounds = session.history.length + Math.max(1, extraRounds || 10);
    session.finished = false;
    session.current = nextPair(session);
    session.updatedAt = Date.now();
    return session;
  }

  /* ---- Read models ----------------------------------------------------- */

  function standings(session) {
    return session.order.map(function (id) {
      var item = session.items[id];
      var decided = item.wins + item.losses;
      return {
        id: item.id,
        name: item.name,
        meta: item.meta,
        rating: item.rating,
        score: Math.round(item.rating),
        played: item.played,
        wins: item.wins,
        losses: item.losses,
        ties: item.ties,
        winRate: decided ? item.wins / decided : 0,
        /* How much this rating should be trusted: it takes a handful of
         * comparisons before a position means anything. */
        confidence: Math.min(1, item.played / 6)
      };
    }).sort(function (x, y) {
      if (Math.abs(y.rating - x.rating) > 1e-9) return y.rating - x.rating;
      if (y.wins !== x.wins) return y.wins - x.wins;
      return x.name.localeCompare(y.name);
    }).map(function (row, index) {
      row.rank = index + 1;
      return row;
    });
  }

  function maxUsefulRounds(n) {
    if (n < 2) return 0;
    return Math.max(n, Math.round(n * Math.log2(n) * 0.9));
  }

  function progress(session) {
    var rounds = session.history.length;
    var target = session.targetRounds || maxUsefulRounds(session.order.length);
    var minPlayed = Infinity;
    session.order.forEach(function (id) {
      minPlayed = Math.min(minPlayed, session.items[id].played);
    });
    if (!isFinite(minPlayed)) minPlayed = 0;
    return {
      rounds: rounds,
      target: target,
      remaining: Math.max(0, target - rounds),
      ratio: target ? Math.min(1, rounds / target) : 1,
      /* Coverage lags progress while some items have barely been seen. */
      coverage: Math.min(1, minPlayed / 3),
      leastSeen: minPlayed
    };
  }

  var Engine = {
    BASE_RATING: BASE_RATING,
    RATING_SCALE: RATING_SCALE,
    makeRng: makeRng,
    winProbability: winProbability,
    createSession: createSession,
    refit: refit,
    nextPair: nextPair,
    submit: submit,
    skip: skip,
    undo: undo,
    extend: extend,
    standings: standings,
    progress: progress,
    maxUsefulRounds: maxUsefulRounds
  };

  if (typeof module !== 'undefined' && module.exports) module.exports = Engine;
  global.Engine = Engine;
})(typeof globalThis !== 'undefined' ? globalThis : this);
