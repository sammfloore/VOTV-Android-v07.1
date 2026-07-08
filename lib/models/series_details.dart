class EpisodeItem {
  const EpisodeItem({
    required this.id,
    required this.title,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.description,
    required this.durationLabel,
    required this.imageUrl,
    required this.streamUrls,
    this.rating = 0,
  });

  final String id;
  final String title;
  final int seasonNumber;
  final int episodeNumber;
  final String description;
  final String durationLabel;
  final String imageUrl;
  final List<String> streamUrls;
  final double rating;

  String get numberLabel => 'T$seasonNumber:E$episodeNumber';
}

class SeriesDetails {
  const SeriesDetails({
    required this.seriesId,
    required this.seasons,
  });

  final String seriesId;
  final Map<int, List<EpisodeItem>> seasons;

  List<int> get seasonNumbers {
    final values = seasons.keys.toList()..sort();
    return values;
  }

  List<EpisodeItem> get allEpisodes {
    final values = <EpisodeItem>[];
    for (final season in seasonNumbers) {
      values.addAll(seasons[season] ?? const []);
    }
    return values;
  }

  EpisodeItem? findEpisode(String episodeId) {
    for (final episode in allEpisodes) {
      if (episode.id == episodeId) return episode;
    }
    return null;
  }
}
