/// Dart port of the prototype's engine.js (and of the server's C# port).
///
/// A session holds a pool of items. Every round the engine offers two of them;
/// the answer is appended to the history. The history is the only source of
/// truth: ratings are re-derived from it, which makes undo exact and lets a
/// session be stored as plain JSON and resumed anywhere.
///
/// Ratings come from a Bradley–Terry fit (Hunter's MM iteration), regularised
/// by a half-win/half-loss against a virtual average opponent. Pairing scores
/// every candidate pair and serves the most informative one.
library;

import 'dart:math' as math;

const double baseRating = 1500;
const double ratingScale = 400;
const double _never = 100000;
const double _prior = 0.5;
const int _maxIterations = 400;
const double _tolerance = 1e-10;

enum PairingMode { smart, gauntlet }

/// Mulberry32, identical to the prototype so sessions replay the same way.
double Function() makeRng(int seed) {
  var t = seed & 0xFFFFFFFF;
  if (t == 0) t = 1;
  return () {
    t = (t + 0x6D2B79F5) & 0xFFFFFFFF;
    var r = t;
    r = _imul(r ^ (r >> 15), r | 1);
    r ^= (r + _imul(r ^ (r >> 7), r | 61)) & 0xFFFFFFFF;
    return ((r ^ (r >> 14)) & 0xFFFFFFFF) / 4294967296.0;
  };
}

/// 32-bit multiply that stays exact on the web, where ints are doubles.
int _imul(int a, int b) {
  final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
  final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
  return (al * bl + ((((ah * bl + al * bh) & 0xFFFF) << 16) & 0xFFFFFFFF)) & 0xFFFFFFFF;
}

String pairKey(String a, String b) => a.compareTo(b) < 0 ? '$a|$b' : '$b|$a';

double winProbability(double ratingA, double ratingB) =>
    1 / (1 + math.pow(10, (ratingB - ratingA) / ratingScale));

int maxUsefulRounds(int n) {
  if (n < 2) return 0;
  return math.max(n, (n * (math.log(n) / math.ln2) * 0.9).round());
}

class EngineItem {
  EngineItem({required this.id, required this.name, this.detail = ''});

  final String id;
  final String name;
  final String detail;
  double rating = baseRating;
  int played = 0;
  int wins = 0;
  int losses = 0;
  int ties = 0;

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'detail': detail, 'rating': rating,
        'played': played, 'wins': wins, 'losses': losses, 'ties': ties,
      };

  factory EngineItem.fromJson(Map<String, dynamic> j) => EngineItem(
        id: j['id'] as String, name: j['name'] as String, detail: (j['detail'] ?? '') as String)
    ..rating = (j['rating'] as num).toDouble()
    ..played = j['played'] as int
    ..wins = j['wins'] as int
    ..losses = j['losses'] as int
    ..ties = j['ties'] as int;
}

class Round {
  const Round(this.a, this.b, this.winner, this.previousChampion, this.at);

  final String a;
  final String b;

  /// Null for "too close to call".
  final String? winner;
  final String? previousChampion;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'a': a, 'b': b, 'w': winner, 'pc': previousChampion, 'at': at.toUtc().toIso8601String()};

  factory Round.fromJson(Map<String, dynamic> j) =>
      Round(j['a'] as String, j['b'] as String, j['w'] as String?, j['pc'] as String?, DateTime.parse(j['at'] as String));
}

class Standing {
  const Standing({
    required this.rank, required this.item, required this.winRate, required this.confidence,
  });

  final int rank;
  final EngineItem item;
  final double winRate;

  /// 0..1: it takes a handful of comparisons before a position means anything.
  final double confidence;
}

class Progress {
  const Progress(this.rounds, this.target, this.coverage, this.leastSeen);

  final int rounds;
  final int target;
  final double coverage;
  final int leastSeen;

  int get remaining => math.max(0, target - rounds);
  double get ratio => target == 0 ? 1 : math.min(1, rounds / target);
}

class RankingSession {
  RankingSession({required this.mode, required this.seed, required this.targetRounds});

  final Map<String, EngineItem> items = {};
  final List<String> order = [];
  final List<Round> history = [];
  final Map<String, int> pairSeen = {};
  final PairingMode mode;
  final int seed;
  int targetRounds;
  int skips = 0;
  String? champion;
  List<String>? current;
  bool finished = false;

  /// Creates a session and serves the opening pair.
  factory RankingSession.create(
    Iterable<EngineItem> pool, {
    PairingMode mode = PairingMode.smart,
    required int seed,
    required int targetRounds,
  }) {
    final s = RankingSession(mode: mode, seed: seed, targetRounds: targetRounds);
    for (final item in pool) {
      if (s.items.containsKey(item.id)) continue;
      s.items[item.id] = item;
      s.order.add(item.id);
    }
    if (s.order.length < 2) throw ArgumentError('A session needs at least 2 items');
    s.current = s.nextPair();
    return s;
  }

  // ---- Rating model ------------------------------------------------------

  void refit() {
    final n = order.length;
    final index = {for (var i = 0; i < n; i++) order[i]: i};
    final wins = List<double>.filled(n, 0);
    final counts = List.generate(n, (_) => <int, double>{});

    for (final r in history) {
      final a = index[r.a], b = index[r.b];
      if (a == null || b == null) continue;
      counts[a][b] = (counts[a][b] ?? 0) + 1;
      counts[b][a] = (counts[b][a] ?? 0) + 1;
      if (r.winner == null) {
        wins[a] += 0.5;
        wins[b] += 0.5;
      } else if (r.winner == r.a) {
        wins[a] += 1;
      } else {
        wins[b] += 1;
      }
    }

    final strength = List<double>.filled(n, 1);
    for (var iter = 0; iter < _maxIterations; iter++) {
      var maxDelta = 0.0;
      for (var i = 0; i < n; i++) {
        var denominator = 2 * _prior / (strength[i] + 1);
        counts[i].forEach((j, c) => denominator += c / (strength[i] + strength[j]));
        final next = (wins[i] + _prior) / denominator;
        maxDelta = math.max(maxDelta, (next - strength[i]).abs() / (strength[i] == 0 ? 1 : strength[i]));
        strength[i] = next;
      }
      var logSum = 0.0;
      for (final s in strength) {
        logSum += math.log(s);
      }
      final scale = math.exp(logSum / n);
      for (var i = 0; i < n; i++) {
        strength[i] /= scale;
      }
      if (maxDelta < _tolerance) break;
    }

    for (var i = 0; i < n; i++) {
      items[order[i]]!.rating = baseRating + ratingScale * (math.log(strength[i]) / math.ln10);
    }
  }

  // ---- Pairing -----------------------------------------------------------

  double Function() _rng() => makeRng(seed + history.length * 7919 + skips * 104729);

  List<String>? nextPair() {
    if (order.length < 2) return null;
    final random = _rng();
    final minPlayed = order.map((id) => items[id]!.played).reduce(math.min);
    final champ = mode == PairingMode.gauntlet && champion != null && items.containsKey(champion) ? champion : null;
    final bench = {...?current}..remove(champ);

    final pairs = <({String a, String b, double cost})>[];
    for (var i = 0; i < order.length; i++) {
      for (var j = i + 1; j < order.length; j++) {
        final a = items[order[i]]!, b = items[order[j]]!;
        if (champ != null && a.id != champ && b.id != champ) continue;
        final seen = pairSeen[pairKey(a.id, b.id)] ?? 0;
        final cost = (a.rating - b.rating).abs() +
            seen * _never +
            ((bench.contains(a.id) ? 1 : 0) + (bench.contains(b.id) ? 1 : 0)) * _never +
            (a.played - minPlayed) * 70 +
            (b.played - minPlayed) * 70;
        pairs.add((a: a.id, b: b.id, cost: cost));
      }
    }
    if (pairs.isEmpty) return null;

    // List.sort is not stable in Dart, so keep scan order explicitly on ties.
    final indexed = pairs.indexed.toList()
      ..sort((x, y) {
        final c = x.$2.cost.compareTo(y.$2.cost);
        return c != 0 ? c : x.$1.compareTo(y.$1);
      });
    final best = indexed.first.$2.cost;
    final shortlist = indexed.map((e) => e.$2).where((p) => p.cost <= best + 40).take(3).toList();
    final chosen = shortlist[(random() * shortlist.length).floor()];

    if (champ != null) {
      // The champion holds its slot; only the challenger swaps in.
      final challenger = chosen.a == champ ? chosen.b : chosen.a;
      final held = current?.indexOf(champ) ?? -1;
      return held == 1 ? [challenger, champ] : [champ, challenger];
    }
    return random() < 0.5 ? [chosen.a, chosen.b] : [chosen.b, chosen.a];
  }

  // ---- Mutations ---------------------------------------------------------

  void submit(String? winnerId, {DateTime? at}) {
    final pair = current;
    if (pair == null) return;
    final a = pair[0], b = pair[1];
    if (winnerId != null && winnerId != a && winnerId != b) {
      throw ArgumentError('Winner must be one of the two shown items');
    }
    history.add(Round(a, b, winnerId, champion, at ?? DateTime.now().toUtc()));
    _tally(items[a]!, items[b]!, winnerId, a, 1);
    final key = pairKey(a, b);
    pairSeen[key] = (pairSeen[key] ?? 0) + 1;
    champion = winnerId ?? champion;
    refit();
    if (targetRounds > 0 && history.length >= targetRounds) {
      finished = true;
      current = null;
    } else {
      current = nextPair();
    }
  }

  void skip() {
    final pair = current;
    if (pair == null) return;
    final key = pairKey(pair[0], pair[1]);
    pairSeen[key] = (pairSeen[key] ?? 0) + 1;
    skips++;
    current = nextPair();
  }

  void undo() {
    if (history.isEmpty) return;
    final last = history.removeLast();
    _tally(items[last.a]!, items[last.b]!, last.winner, last.a, -1);
    final key = pairKey(last.a, last.b);
    pairSeen[key] = math.max(0, (pairSeen[key] ?? 1) - 1);
    champion = last.previousChampion;
    finished = false;
    current = [last.a, last.b];
    refit();
  }

  void extend([int extraRounds = 10]) {
    targetRounds = history.length + math.max(1, extraRounds);
    finished = false;
    current = nextPair();
  }

  /// Ends the session early with the ranking as it stands.
  void finishNow() {
    finished = true;
    current = null;
  }

  // ---- Read models -------------------------------------------------------

  List<Standing> standings() {
    final sorted = order.map((id) => items[id]!).toList()
      ..sort((x, y) {
        if ((y.rating - x.rating).abs() > 1e-9) return y.rating.compareTo(x.rating);
        if (y.wins != x.wins) return y.wins.compareTo(x.wins);
        return x.name.compareTo(y.name);
      });
    return [
      for (var i = 0; i < sorted.length; i++)
        Standing(
          rank: i + 1,
          item: sorted[i],
          winRate: sorted[i].wins + sorted[i].losses == 0 ? 0 : sorted[i].wins / (sorted[i].wins + sorted[i].losses),
          confidence: math.min(1, sorted[i].played / 6),
        ),
    ];
  }

  Progress progress() {
    final target = targetRounds > 0 ? targetRounds : maxUsefulRounds(order.length);
    final least = order.isEmpty ? 0 : order.map((id) => items[id]!.played).reduce(math.min);
    return Progress(history.length, target, math.min(1, least / 3), least);
  }

  static void _tally(EngineItem a, EngineItem b, String? winner, String aId, int sign) {
    a.played += sign;
    b.played += sign;
    if (winner == null) {
      a.ties += sign;
      b.ties += sign;
    } else if (winner == aId) {
      a.wins += sign;
      b.losses += sign;
    } else {
      b.wins += sign;
      a.losses += sign;
    }
  }

  // ---- Persistence -------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'items': [for (final id in order) items[id]!.toJson()],
        'history': [for (final r in history) r.toJson()],
        'pairSeen': pairSeen,
        'mode': mode.name,
        'seed': seed,
        'targetRounds': targetRounds,
        'skips': skips,
        'champion': champion,
        'current': current,
        'finished': finished,
      };

  factory RankingSession.fromJson(Map<String, dynamic> j) {
    final s = RankingSession(
      mode: PairingMode.values.byName(j['mode'] as String),
      seed: j['seed'] as int,
      targetRounds: j['targetRounds'] as int,
    );
    for (final raw in j['items'] as List) {
      final item = EngineItem.fromJson(raw as Map<String, dynamic>);
      s.items[item.id] = item;
      s.order.add(item.id);
    }
    s.history.addAll((j['history'] as List).map((r) => Round.fromJson(r as Map<String, dynamic>)));
    s.pairSeen.addAll((j['pairSeen'] as Map).map((k, v) => MapEntry(k as String, v as int)));
    s.skips = j['skips'] as int? ?? 0;
    s.champion = j['champion'] as String?;
    s.current = (j['current'] as List?)?.cast<String>();
    s.finished = j['finished'] as bool? ?? false;
    return s;
  }
}

/// Picks the pool for a level: unlocked tiers only, famous first, shuffled within each tier.
List<T> buildPool<T>(List<T> items, int Function(T) tierOf, List<int> tiers, int poolSize, double Function() random) {
  final byTier = <int, List<T>>{};
  for (final item in items) {
    final tier = tierOf(item);
    if (tiers.contains(tier)) (byTier[tier] ??= []).add(item);
  }
  final ordered = <T>[];
  for (final tier in byTier.keys.toList()..sort()) {
    final bucket = byTier[tier]!;
    for (var i = bucket.length - 1; i > 0; i--) {
      final j = (random() * (i + 1)).floor();
      final tmp = bucket[i];
      bucket[i] = bucket[j];
      bucket[j] = tmp;
    }
    ordered.addAll(bucket);
  }
  return poolSize > 0 ? ordered.take(poolSize).toList() : ordered;
}

int roundsFor(int roundBudget, int poolSize) =>
    roundBudget > 0 ? math.min(roundBudget, maxUsefulRounds(poolSize)) : maxUsefulRounds(poolSize);
