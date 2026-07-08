enum MediaType { movie, series, live }

class MediaItem {
  const MediaItem({
    required this.id,
    this.providerId = '',
    required this.title,
    required this.type,
    required this.year,
    required this.rating,
    required this.description,
    required this.posterUrl,
    required this.backdropUrl,
    required this.genres,
    required this.cast,
    required this.keywords,
    required this.durationLabel,
    this.franchise,
    this.isNew = false,
    this.addedAt = 0,
    this.trailerUrl = '',
    this.streamUrls = const [],
  });

  final String id;
  final String providerId;
  final String title;
  final MediaType type;
  final int year;
  final double rating;
  final String description;
  final String posterUrl;
  final String backdropUrl;
  final List<String> genres;
  final List<String> cast;
  final List<String> keywords;
  final String durationLabel;
  final String? franchise;
  final bool isNew;
  final int addedAt;
  final String trailerUrl;
  final List<String> streamUrls;

  bool get isPlayable => streamUrls.any((url) => url.trim().isNotEmpty);
  bool get isLive => type == MediaType.live;

  String get typeLabel {
    switch (type) {
      case MediaType.movie:
        return 'Película';
      case MediaType.series:
        return 'Serie';
      case MediaType.live:
        return 'En vivo';
    }
  }

  String get searchableText => <String>[
        title,
        description,
        ...genres,
        ...cast,
        ...keywords,
        franchise ?? '',
        year.toString(),
        typeLabel,
      ].join(' ').toLowerCase();

  bool matches(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return query
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .every(searchableText.contains);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'providerId': providerId,
        'title': title,
        'type': type.name,
        'year': year,
        'rating': rating,
        'description': description,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'genres': genres,
        'cast': cast,
        'keywords': keywords,
        'durationLabel': durationLabel,
        'franchise': franchise,
        'isNew': isNew,
        'addedAt': addedAt,
        'trailerUrl': trailerUrl,
        'streamUrls': streamUrls,
      };

  factory MediaItem.fromMap(Map<String, dynamic> map) {
    return MediaItem(
      id: '${map['id'] ?? ''}',
      providerId: '${map['providerId'] ?? ''}',
      title: '${map['title'] ?? ''}',
      type: _typeFromName('${map['type'] ?? ''}'),
      year: _asInt(map['year']),
      rating: _asDouble(map['rating']),
      description: '${map['description'] ?? ''}',
      posterUrl: '${map['posterUrl'] ?? ''}',
      backdropUrl: '${map['backdropUrl'] ?? ''}',
      genres: _stringList(map['genres']),
      cast: _stringList(map['cast']),
      keywords: _stringList(map['keywords']),
      durationLabel: '${map['durationLabel'] ?? ''}',
      franchise: _nullableString(map['franchise']),
      isNew: map['isNew'] == true,
      addedAt: _asInt(map['addedAt']),
      trailerUrl: '${map['trailerUrl'] ?? ''}',
      streamUrls: _stringList(map['streamUrls']),
    );
  }

  static MediaType _typeFromName(String value) {
    return MediaType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => MediaType.movie,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => '$item')
        .where((item) => item.isNotEmpty && item.toLowerCase() != 'null')
        .toList(growable: false);
  }

  static String? _nullableString(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }
}
