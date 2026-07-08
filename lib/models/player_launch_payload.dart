import 'dart:convert';

import 'media_item.dart';
import 'series_details.dart';

class PlayerEpisodePayload {
  const PlayerEpisodePayload({
    required this.episode,
    required this.urls,
    required this.initialProgress,
    required this.previewImageUrl,
  });

  final EpisodeItem episode;
  final List<String> urls;
  final double initialProgress;
  final String previewImageUrl;

  Map<String, dynamic> toMap() => {
        'episode': {
          'id': episode.id,
          'title': episode.title,
          'seasonNumber': episode.seasonNumber,
          'episodeNumber': episode.episodeNumber,
          'durationLabel': episode.durationLabel,
          'imageUrl': episode.imageUrl,
        },
        'urls': urls,
        'initialProgress': initialProgress,
        'previewImageUrl': previewImageUrl,
      };

  factory PlayerEpisodePayload.fromMap(Map<String, dynamic> map) {
    final episodeMap = Map<String, dynamic>.from(
      map['episode'] as Map? ?? const <String, dynamic>{},
    );
    return PlayerEpisodePayload(
      episode: EpisodeItem(
        id: '${episodeMap['id'] ?? ''}',
        title: '${episodeMap['title'] ?? ''}',
        seasonNumber: _asInt(episodeMap['seasonNumber']),
        episodeNumber: _asInt(episodeMap['episodeNumber']),
        description: '',
        durationLabel: '${episodeMap['durationLabel'] ?? ''}',
        imageUrl: '${episodeMap['imageUrl'] ?? ''}',
        streamUrls: _stringList(map['urls']),
      ),
      urls: _stringList(map['urls']),
      initialProgress: _asDouble(map['initialProgress']),
      previewImageUrl: '${map['previewImageUrl'] ?? ''}',
    );
  }
}

class PlayerLaunchPayload {
  const PlayerLaunchPayload({
    required this.title,
    required this.urls,
    required this.isLive,
    this.subtitle,
    this.initialProgress = 0,
    this.previewImageUrl = '',
    this.mediaItem,
    this.episodes = const [],
    this.initialEpisodeId,
    this.progressEpisodeId,
  });

  final String title;
  final String? subtitle;
  final List<String> urls;
  final bool isLive;
  final double initialProgress;
  final String previewImageUrl;
  final MediaItem? mediaItem;
  final List<PlayerEpisodePayload> episodes;
  final String? initialEpisodeId;
  final String? progressEpisodeId;

  bool get isSeriesPlayback => mediaItem?.type == MediaType.series && episodes.isNotEmpty;

  SeriesDetails? get seriesDetails {
    final item = mediaItem;
    if (item == null || episodes.isEmpty) return null;
    final grouped = <int, List<EpisodeItem>>{};
    for (final entry in episodes) {
      grouped.putIfAbsent(entry.episode.seasonNumber, () => <EpisodeItem>[])
        ..add(entry.episode);
    }
    return SeriesDetails(seriesId: item.id, seasons: grouped);
  }

  String toJson() => jsonEncode(toMap());

  Map<String, dynamic> toMap() => {
        'title': title,
        'subtitle': subtitle,
        'urls': urls,
        'isLive': isLive,
        'initialProgress': initialProgress,
        'previewImageUrl': previewImageUrl,
        'mediaItem': mediaItem == null
            ? null
            : {
                'id': mediaItem!.id,
                'providerId': mediaItem!.providerId,
                'title': mediaItem!.title,
                'type': mediaItem!.type.name,
                'year': mediaItem!.year,
                'posterUrl': mediaItem!.posterUrl,
                'backdropUrl': mediaItem!.backdropUrl,
              },
        'episodes': episodes.map((entry) => entry.toMap()).toList(),
        'initialEpisodeId': initialEpisodeId,
        'progressEpisodeId': progressEpisodeId,
      };

  factory PlayerLaunchPayload.fromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Los datos del reproductor no son válidos.');
    }
    return PlayerLaunchPayload.fromMap(Map<String, dynamic>.from(decoded));
  }

  factory PlayerLaunchPayload.fromMap(Map<String, dynamic> map) {
    final mediaMap = map['mediaItem'];
    final rawEpisodes = map['episodes'];
    return PlayerLaunchPayload(
      title: '${map['title'] ?? ''}',
      subtitle: _nullableString(map['subtitle']),
      urls: _stringList(map['urls']),
      isLive: map['isLive'] == true,
      initialProgress: _asDouble(map['initialProgress']),
      previewImageUrl: '${map['previewImageUrl'] ?? ''}',
      mediaItem: mediaMap is Map
          ? MediaItem.fromMap(Map<String, dynamic>.from(mediaMap))
          : null,
      episodes: rawEpisodes is List
          ? rawEpisodes
              .whereType<Map>()
              .map(
                (entry) => PlayerEpisodePayload.fromMap(
                  Map<String, dynamic>.from(entry),
                ),
              )
              .toList(growable: false)
          : const [],
      initialEpisodeId: _nullableString(map['initialEpisodeId']),
      progressEpisodeId: _nullableString(map['progressEpisodeId']),
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => '$item')
      .where((item) => item.trim().isNotEmpty && item.toLowerCase() != 'null')
      .toList(growable: false);
}

String? _nullableString(dynamic value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty || text.toLowerCase() == 'null' ? null : text;
}
