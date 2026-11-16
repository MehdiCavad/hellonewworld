import '../engine/ranking_engine.dart';
import 'models.dart';

/// A ranking as the device keeps it: the engine state plus what the UI
/// needs to draw it (topic look, item media) without the network.
class SavedSession {
  SavedSession({
    required this.id,
    required this.topic,
    required this.level,
    required this.engine,
    required this.itemMeta,
    required this.createdAt,
    required this.updatedAt,
    this.dirty = true,
  });

  final String id;
  final Topic topic;
  final Level level;
  final RankingSession engine;
  final Map<String, Item> itemMeta;
  final DateTime createdAt;
  DateTime updatedAt;

  /// True until the server has the latest history.
  bool dirty;

  bool get finished => engine.finished;
  bool get uploadable => itemMeta.values.every((i) => i.isServerItem);

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic.toJson(),
        'level': level.toJson(),
        'engine': engine.toJson(),
        'items': [for (final i in itemMeta.values) i.toJson()],
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'dirty': dirty,
      };

  factory SavedSession.fromJson(Map<String, dynamic> j) {
    final items = [for (final i in j['items'] as List) Item.fromJson(i as Map<String, dynamic>)];
    return SavedSession(
      id: j['id'] as String,
      topic: Topic.fromJson(j['topic'] as Map<String, dynamic>),
      level: Level.fromJson(j['level'] as Map<String, dynamic>),
      engine: RankingSession.fromJson(j['engine'] as Map<String, dynamic>),
      itemMeta: {for (final i in items) i.id: i},
      createdAt: DateTime.parse(j['createdAt'] as String),
      updatedAt: DateTime.parse(j['updatedAt'] as String),
      dirty: j['dirty'] as bool? ?? true,
    );
  }

  /// The upload body for PUT /sessions/{id}: the whole history, keyed by sequence.
  Map<String, dynamic> toUpload() => {
        'topicSlug': topic.slug,
        'levelId': level.id,
        'mode': engine.mode == PairingMode.gauntlet ? 'gauntlet' : 'smart',
        'seed': engine.seed,
        'targetRounds': engine.targetRounds,
        'status': finished ? 'finished' : 'active',
        'poolItemIds': [for (final id in engine.order) int.parse(id)],
        'comparisons': [
          for (final (i, r) in engine.history.indexed)
            {
              'seq': i,
              'a': int.parse(r.a),
              'b': int.parse(r.b),
              'outcome': r.winner == null ? 'tie' : (r.winner == r.a ? 'a' : 'b'),
              'at': r.at.toUtc().toIso8601String(),
            },
        ],
        'createdAt': createdAt.toUtc().toIso8601String(),
      };
}
