import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rankd/engine/ranking_engine.dart';

RankingSession newSession(int n, {PairingMode mode = PairingMode.smart, int target = 30, int seed = 42}) =>
    RankingSession.create([for (var i = 0; i < n; i++) EngineItem(id: 'i$i', name: 'Item $i')],
        mode: mode, seed: seed, targetRounds: target);

void main() {
  group('parity with the web prototype', () {
    test('the PRNG matches engine.js bit for bit', () {
      final r = makeRng(42);
      expect([r(), r(), r()], [0.6011037519201636, 0.44829055899754167, 0.8524657934904099]);
    });

    test('the same seed serves the same pairs as engine.js', () {
      final s = newSession(8);
      final seq = <String>[];
      for (var k = 0; k < 10; k++) {
        seq.add(s.current!.join('-'));
        s.submit(s.current![0]);
      }
      expect(seq, ['i0-i2', 'i4-i1', 'i5-i3', 'i7-i6', 'i1-i3', 'i6-i2', 'i4-i7', 'i5-i0', 'i7-i1', 'i0-i6']);
    });
  });

  test('the winner climbs and the loser drops symmetrically', () {
    final s = newSession(8);
    final a = s.current![0], b = s.current![1];
    s.submit(a);
    final gain = s.items[a]!.rating - baseRating;
    final loss = baseRating - s.items[b]!.rating;
    expect(gain, greaterThan(0));
    expect(gain, closeTo(loss, 1e-6));
  });

  test('a tie leaves equal ratings untouched', () {
    final s = newSession(8);
    final a = s.current![0];
    s.submit(null);
    expect(s.items[a]!.rating, closeTo(baseRating, 1e-6));
    expect(s.items[a]!.ties, 1);
  });

  test('undo restores ratings, counters and the pair exactly', () {
    final s = newSession(8);
    s.submit(s.current![1]);
    s.submit(null);
    final before = jsonEncode(s.toJson()['items']);
    final pair = [...s.current!];
    s.submit(pair[0]);
    s.undo();
    expect(jsonEncode(s.toJson()['items']), before);
    expect(s.current, pair);
  });

  test('the session finishes exactly at the target', () {
    final s = newSession(6, target: 10);
    for (var i = 0; i < 10; i++) {
      s.submit(s.current![0]);
    }
    expect(s.finished, isTrue);
    expect(s.current, isNull);
  });

  test('smart duels never show an option in two consecutive rounds', () {
    for (final n in [8, 16, 24]) {
      final s = newSession(n, target: maxUsefulRounds(n), seed: n * 11);
      List<String>? prev;
      while (s.current != null) {
        if (prev != null) expect(prev.toSet().intersection(s.current!.toSet()), isEmpty);
        prev = [...s.current!];
        s.submit(s.current![0]);
      }
    }
  });

  test('no pair is asked twice while unasked pairs remain', () {
    final s = newSession(16, target: maxUsefulRounds(16), seed: 16 * 13);
    final seen = <String>{};
    while (s.current != null) {
      expect(seen.add(pairKey(s.current![0], s.current![1])), isTrue);
      s.submit(s.current![1]);
    }
  });

  test('king of the hill freezes the champion on its side', () {
    final s = newSession(10, mode: PairingMode.gauntlet);
    final champion = s.current![0];
    s.submit(champion);
    for (var i = 0; i < 12; i++) {
      expect(s.current![0], champion);
      s.submit(champion);
    }
  });

  test('a clean oracle recovers the exact order of 16 items', () {
    final s = newSession(16, target: maxUsefulRounds(16), seed: 7);
    final rng = makeRng(8);
    int truth(String id) => int.parse(id.substring(1));
    while (s.current != null) {
      final c = s.current!;
      final better = truth(c[0]) > truth(c[1]) ? c[0] : c[1];
      rng();
      s.submit(better);
    }
    final ranked = s.standings();
    expect(ranked.first.item.id, 'i15');
    expect(ranked.last.item.id, 'i0');
    for (var i = 0; i < 16; i++) {
      expect(ranked[i].item.id, 'i${15 - i}');
    }
  });

  test('a session survives a JSON round trip mid-play', () {
    final s = newSession(8);
    s.submit(s.current![0]);
    final restored = RankingSession.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(restored.current, s.current);
    restored.submit(restored.current![0]);
    expect(restored.history.length, 2);
  });

  test('pools respect unlocked tiers and size', () {
    final items = [for (var i = 0; i < 30; i++) (id: i, tier: i % 3 + 1)];
    final pool = buildPool(items, (x) => x.tier, [1], 8, makeRng(9));
    expect(pool, hasLength(8));
    expect(pool.every((x) => x.tier == 1), isTrue);
    expect(roundsFor(0, 36), maxUsefulRounds(36));
  });
}
