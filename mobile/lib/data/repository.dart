import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'models.dart';
import 'saved_session.dart';

enum Source { live, cached, bundled }

class Loaded<T> {
  const Loaded(this.value, this.source);
  final T value;
  final Source source;
}

/// Offline-first data access. Reads try the API, fall back to the last copy
/// on the device, and finally to the catalogue bundled with the app, so the
/// app always opens and every downloaded topic stays playable offline.
class Repository {
  Repository(this._prefs, this.api);

  final SharedPreferences _prefs;
  final ApiClient api;

  static const _kTopics = 'cache.topics';
  static const _kLevels = 'cache.levels';
  static const _kSessions = 'sessions.v2';
  static String _kTopic(String slug) => 'cache.topic.$slug';

  Map<String, dynamic>? _bundled;

  Future<Map<String, dynamic>> _bundle() async =>
      _bundled ??= jsonDecode(await rootBundle.loadString('assets/data/catalogue.json')) as Map<String, dynamic>;

  // ---- Catalogue ---------------------------------------------------------

  Future<Loaded<List<Topic>>> topics() async {
    try {
      final live = await api.topics();
      await _prefs.setString(_kTopics, jsonEncode([for (final t in live) t.toJson()]));
      return Loaded(live, Source.live);
    } catch (_) {
      final cached = _prefs.getString(_kTopics);
      if (cached != null) {
        return Loaded([for (final t in jsonDecode(cached) as List) Topic.fromJson(t as Map<String, dynamic>)], Source.cached);
      }
      return Loaded(await _bundledTopics(), Source.bundled);
    }
  }

  Future<List<Level>> levels() async {
    try {
      final live = await api.levels();
      await _prefs.setString(_kLevels, jsonEncode([for (final l in live) l.toJson()]));
      return live;
    } catch (_) {
      final cached = _prefs.getString(_kLevels);
      final raw = cached != null ? jsonDecode(cached) as List : (await _bundle())['levels'] as List;
      return [for (final l in raw) Level.fromJson(l as Map<String, dynamic>)];
    }
  }

  Future<List<Item>> items(Topic topic) async {
    try {
      final live = await api.topicItems(topic.slug);
      await _prefs.setString(_kTopic(topic.slug), jsonEncode([for (final i in live) i.toJson()]));
      return live;
    } catch (_) {
      final cached = _prefs.getString(_kTopic(topic.slug));
      if (cached != null) return [for (final i in jsonDecode(cached) as List) Item.fromJson(i as Map<String, dynamic>)];
      final t = ((await _bundle())['topics'] as List).cast<Map<String, dynamic>>().firstWhere((t) => t['slug'] == topic.slug);
      return [
        for (final (n, i) in (t['items'] as List).cast<Map<String, dynamic>>().indexed)
          Item(id: 'local:${topic.slug}:$n', name: i['name'] as String, detail: i['detail'] as String? ?? '', tier: i['tier'] as int),
      ];
    }
  }

  Future<List<Topic>> _bundledTopics() async {
    const accents = {
      'movies': '#FF5D5D', 'actors': '#B26BFF', 'footballers': '#22C55E', 'music': '#F59E0B', 'songs': '#F0499B',
      'food': '#FF8A3D', 'languages': '#3B82F6', 'cities': '#14B8A6', 'series': '#7C5CFF',
    };
    return [
      for (final t in ((await _bundle())['topics'] as List).cast<Map<String, dynamic>>())
        Topic(
          slug: t['slug'] as String,
          name: t['name'] as String,
          emoji: t['emoji'] as String,
          description: t['blurb'] as String,
          mediaKind: t['mediaKind'] as String,
          accentHex: accents[t['slug']] ?? '#7C5CFF',
          itemCount: (t['items'] as List).length,
          itemsPerTier: {
            for (final tier in [1, 2, 3]) tier: (t['items'] as List).where((i) => (i as Map)['tier'] == tier).length,
          },
        ),
    ];
  }

  // ---- Sessions ----------------------------------------------------------

  List<SavedSession> loadSessions() {
    final raw = _prefs.getString(_kSessions);
    if (raw == null) return [];
    try {
      return [for (final s in jsonDecode(raw) as List) SavedSession.fromJson(s as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSessions(List<SavedSession> sessions) =>
      _prefs.setString(_kSessions, jsonEncode([for (final s in sessions) s.toJson()]));

  Future<int>? _inFlight;
  List<SavedSession>? _queued;

  /// Uploads every session the server has not seen yet. Failures are kept for next time.
  /// One upload runs at a time; a call made meanwhile runs once the current one ends.
  Future<int> sync(List<SavedSession> sessions) {
    if (_inFlight != null) {
      _queued = sessions;
      return _inFlight!;
    }
    final run = _syncOnce(sessions).whenComplete(() {
      _inFlight = null;
      final next = _queued;
      _queued = null;
      if (next != null) sync(next);
    });
    return _inFlight = run;
  }

  Future<int> _syncOnce(List<SavedSession> sessions) async {
    var uploaded = 0;
    for (final s in sessions.where((s) => s.dirty && s.uploadable && s.engine.history.isNotEmpty).toList()) {
      final stamp = s.updatedAt;
      try {
        await api.putSession(s.id, s.toUpload());
        // Answers given while the upload was in flight still need sending.
        if (s.updatedAt == stamp) s.dirty = false;
        uploaded++;
      } catch (_) {
        break; // offline: try again later
      }
    }
    return uploaded; // the caller persists the cleared dirty flags from its current state
  }

  Future<void> clearLocal() async {
    final keep = {'device.id'};
    for (final k in _prefs.getKeys().where((k) => !keep.contains(k)).toList()) {
      await _prefs.remove(k);
    }
  }
}
