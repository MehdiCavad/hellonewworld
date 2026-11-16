import 'dart:ui' show Color;

/// Catalogue and session models. Field names follow the Rankd API (v1).

class Media {
  const Media({required this.url, required this.provider, this.sourceUrl, this.licence = '', this.attribution = ''});

  final String url;
  final String provider;
  final String? sourceUrl;
  final String licence;
  final String attribution;

  factory Media.fromJson(Map<String, dynamic> j) => Media(
        url: j['url'] as String,
        provider: j['provider'] as String? ?? '',
        sourceUrl: j['sourceUrl'] as String?,
        licence: j['licence'] as String? ?? '',
        attribution: j['attribution'] as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'url': url, 'provider': provider, 'sourceUrl': sourceUrl, 'licence': licence, 'attribution': attribution};
}

class Item {
  const Item({required this.id, required this.name, this.detail = '', this.tier = 1, this.image, this.audio});

  /// The server's id as a string, or "local:…" for items from the bundled catalogue.
  final String id;
  final String name;
  final String detail;
  final int tier;
  final Media? image;
  final Media? audio;

  bool get isServerItem => int.tryParse(id) != null;

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'].toString(),
        name: j['name'] as String,
        detail: j['detail'] as String? ?? '',
        tier: j['tier'] as int? ?? 1,
        image: j['image'] == null ? null : Media.fromJson(j['image'] as Map<String, dynamic>),
        audio: j['audio'] == null ? null : Media.fromJson(j['audio'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'detail': detail, 'tier': tier, 'image': image?.toJson(), 'audio': audio?.toJson()};
}

class Topic {
  const Topic({
    required this.slug,
    required this.name,
    required this.emoji,
    required this.description,
    required this.mediaKind,
    required this.accentHex,
    required this.itemCount,
    required this.itemsPerTier,
    this.coverImageUrl,
  });

  final String slug;
  final String name;
  final String emoji;
  final String description;
  final String mediaKind;
  final String accentHex;
  final int itemCount;
  final Map<int, int> itemsPerTier;
  final String? coverImageUrl;

  Color get accent => Color(int.parse('FF${accentHex.replaceFirst('#', '')}', radix: 16));
  bool get hasPreviews => mediaKind == 'itunes:song';

  factory Topic.fromJson(Map<String, dynamic> j) => Topic(
        slug: j['slug'] as String,
        name: j['name'] as String,
        emoji: j['emoji'] as String? ?? '⭐',
        description: j['description'] as String? ?? '',
        mediaKind: j['mediaKind'] as String? ?? 'wikipedia',
        accentHex: j['accent'] as String? ?? '#7C5CFF',
        itemCount: j['itemCount'] as int? ?? 0,
        itemsPerTier: ((j['itemsPerTier'] as Map?) ?? {}).map((k, v) => MapEntry(int.parse(k.toString()), v as int)),
        coverImageUrl: j['coverImageUrl'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'slug': slug, 'name': name, 'emoji': emoji, 'description': description, 'mediaKind': mediaKind,
        'accent': accentHex, 'itemCount': itemCount,
        'itemsPerTier': itemsPerTier.map((k, v) => MapEntry('$k', v)), 'coverImageUrl': coverImageUrl,
      };

  int countFor(Level level) {
    final unlocked = level.tiers.fold<int>(0, (sum, t) => sum + (itemsPerTier[t] ?? 0));
    return level.poolSize > 0 ? (unlocked < level.poolSize ? unlocked : level.poolSize) : unlocked;
  }
}

class TopicDetail {
  const TopicDetail({required this.topic, required this.items});

  final Topic topic;
  final List<Item> items;
}

class Level {
  const Level({
    required this.id,
    required this.name,
    required this.emoji,
    required this.description,
    required this.tiers,
    required this.poolSize,
    required this.roundBudget,
  });

  final String id;
  final String name;
  final String emoji;
  final String description;
  final List<int> tiers;
  final int poolSize;
  final int roundBudget;

  factory Level.fromJson(Map<String, dynamic> j) => Level(
        id: j['id'] as String,
        name: j['name'] as String,
        emoji: j['emoji'] as String? ?? '',
        description: (j['description'] ?? j['blurb'] ?? '') as String,
        tiers: (j['tiers'] as List).cast<int>(),
        poolSize: j['poolSize'] as int,
        roundBudget: j['roundBudget'] as int,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'emoji': emoji, 'description': description, 'tiers': tiers,
        'poolSize': poolSize, 'roundBudget': roundBudget,
      };
}

class GlobalRow {
  const GlobalRow({
    required this.rank,
    this.previousRank,
    required this.itemId,
    required this.name,
    required this.detail,
    required this.rating,
    required this.comparisons,
    required this.wins,
    required this.losses,
    this.image,
  });

  final int rank;
  final int? previousRank;
  final int itemId;
  final String name;
  final String detail;
  final double rating;
  final int comparisons;
  final int wins;
  final int losses;
  final Media? image;

  factory GlobalRow.fromJson(Map<String, dynamic> j) => GlobalRow(
        rank: j['rank'] as int,
        previousRank: j['previousRank'] as int?,
        itemId: j['itemId'] as int,
        name: j['name'] as String,
        detail: j['detail'] as String? ?? '',
        rating: (j['rating'] as num).toDouble(),
        comparisons: j['comparisons'] as int,
        wins: j['wins'] as int,
        losses: j['losses'] as int,
        image: j['image'] == null ? null : Media.fromJson(j['image'] as Map<String, dynamic>),
      );
}

class GlobalRanking {
  const GlobalRanking({required this.devices, required this.rows, this.computedAt});

  final int devices;
  final List<GlobalRow> rows;
  final DateTime? computedAt;

  factory GlobalRanking.fromJson(Map<String, dynamic> j) => GlobalRanking(
        devices: j['devices'] as int? ?? 0,
        computedAt: j['computedAt'] == null ? null : DateTime.parse(j['computedAt'] as String),
        rows: [for (final r in j['rows'] as List) GlobalRow.fromJson(r as Map<String, dynamic>)],
      );
}

class Attribution {
  const Attribution({required this.provider, required this.notice, required this.url, required this.assets});

  final String provider;
  final String notice;
  final String url;
  final int assets;

  factory Attribution.fromJson(Map<String, dynamic> j) => Attribution(
        provider: j['provider'] as String,
        notice: j['notice'] as String,
        url: j['url'] as String,
        assets: j['assets'] as int? ?? 0,
      );
}
