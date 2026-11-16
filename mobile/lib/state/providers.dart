import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../data/api_client.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/saved_session.dart';
import '../engine/ranking_engine.dart';

/// Overridden in main() once SharedPreferences is ready.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

/// The anonymous identity: a random UUID created on first launch (FR-17).
final deviceIdProvider = Provider<String>((ref) {
  final prefs = ref.watch(prefsProvider);
  var id = prefs.getString('device.id');
  if (id == null) {
    id = const Uuid().v4();
    prefs.setString('device.id', id);
  }
  return id;
});

final repositoryProvider = Provider<Repository>((ref) {
  final platform = kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
  return Repository(ref.watch(prefsProvider), ApiClient(deviceId: ref.watch(deviceIdProvider), platform: platform));
});

final topicsProvider = FutureProvider<Loaded<List<Topic>>>((ref) => ref.watch(repositoryProvider).topics());
final levelsProvider = FutureProvider<List<Level>>((ref) => ref.watch(repositoryProvider).levels());
final globalRankingProvider =
    FutureProvider.family<GlobalRanking, String>((ref, slug) => ref.watch(repositoryProvider).api.globalRanking(slug));
final attributionsProvider = FutureProvider<List<Attribution>>((ref) => ref.watch(repositoryProvider).api.attributions());

// ---- Theme ---------------------------------------------------------------

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.values.byName(ref.watch(prefsProvider).getString('theme') ?? 'dark');

  void set(ThemeMode mode) {
    state = mode;
    ref.read(prefsProvider).setString('theme', mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class OnboardedNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(prefsProvider).getBool('onboarded') ?? false;

  void done() {
    state = true;
    ref.read(prefsProvider).setBool('onboarded', true);
  }
}

final onboardedProvider = NotifierProvider<OnboardedNotifier, bool>(OnboardedNotifier.new);

// ---- Sessions ------------------------------------------------------------

/// Every ranking on this device, newest first. Mutations persist immediately
/// and upload in the background; a failed upload waits for the next change.
class SessionsNotifier extends Notifier<List<SavedSession>> {
  Repository get _repo => ref.read(repositoryProvider);

  @override
  List<SavedSession> build() {
    final sessions = _repo.loadSessions()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    Future.microtask(_upload);
    return sessions;
  }

  SavedSession? byId(String id) => state.where((s) => s.id == id).firstOrNull;

  Future<SavedSession> start(Topic topic, Level level, PairingMode mode) async {
    final items = await _repo.items(topic);
    final seed = math.Random().nextInt(1 << 30);
    final pool = buildPool(items, (i) => i.tier, level.tiers, level.poolSize, makeRng(seed));
    final engine = RankingSession.create(
      [for (final i in pool) EngineItem(id: i.id, name: i.name, detail: i.detail)],
      mode: mode,
      seed: seed,
      targetRounds: roundsFor(level.roundBudget, pool.length),
    );
    final now = DateTime.now().toUtc();
    final session = SavedSession(
      id: const Uuid().v4(),
      topic: topic,
      level: level,
      engine: engine,
      itemMeta: {for (final i in pool) i.id: i},
      createdAt: now,
      updatedAt: now,
    );
    state = [session, ...state];
    await _persist();
    return session;
  }

  /// Applies a change to a session's engine, then saves and syncs.
  void mutate(String id, void Function(RankingSession engine) change) {
    final s = byId(id);
    if (s == null) return;
    change(s.engine);
    s.updatedAt = DateTime.now().toUtc();
    s.dirty = true;
    state = [s, ...state.where((x) => x.id != id)];
    _persist();
    // Upload at milestones rather than every tap, and always when finishing.
    if (s.finished || s.engine.history.length % 5 == 0) _upload();
  }

  Future<void> remove(String id) async {
    state = state.where((s) => s.id != id).toList();
    await _persist();
  }

  Future<void> deleteEverything() async {
    try {
      await _repo.api.deleteMyData();
    } catch (_) {
      // Offline or never synced: local data is still cleared below.
    }
    await _repo.clearLocal();
    ref.invalidate(deviceIdProvider);
    state = [];
  }

  Future<void> _persist() => _repo.saveSessions(state);

  Future<void> _upload() async {
    if (await _repo.sync(state) > 0) await _persist();
  }
}

final sessionsProvider = NotifierProvider<SessionsNotifier, List<SavedSession>>(SessionsNotifier.new);

/// The most recent unfinished session, for the home screen's "continue" card.
final resumableProvider = Provider<SavedSession?>(
  (ref) => ref.watch(sessionsProvider).where((s) => !s.finished && s.engine.current != null).firstOrNull,
);
