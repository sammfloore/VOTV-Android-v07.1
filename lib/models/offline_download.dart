class OfflineDownload {
  const OfflineDownload({
    required this.id,
    required this.sourceMediaId,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    required this.localPath,
    required this.downloadedAt,
    required this.sizeBytes,
    this.episodeId,
  });

  final String id;
  final String sourceMediaId;
  final String title;
  final String subtitle;
  final String posterUrl;
  final String localPath;
  final int downloadedAt;
  final int sizeBytes;
  final String? episodeId;

  bool get isEpisode => episodeId != null && episodeId!.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'id': id,
        'sourceMediaId': sourceMediaId,
        'title': title,
        'subtitle': subtitle,
        'posterUrl': posterUrl,
        'localPath': localPath,
        'downloadedAt': downloadedAt,
        'sizeBytes': sizeBytes,
        'episodeId': episodeId,
      };

  factory OfflineDownload.fromMap(Map<String, dynamic> map) {
    return OfflineDownload(
      id: '${map['id'] ?? ''}',
      sourceMediaId: '${map['sourceMediaId'] ?? ''}',
      title: '${map['title'] ?? ''}',
      subtitle: '${map['subtitle'] ?? ''}',
      posterUrl: '${map['posterUrl'] ?? ''}',
      localPath: '${map['localPath'] ?? ''}',
      downloadedAt: int.tryParse('${map['downloadedAt'] ?? 0}') ?? 0,
      sizeBytes: int.tryParse('${map['sizeBytes'] ?? 0}') ?? 0,
      episodeId: _nullable('${map['episodeId'] ?? ''}'),
    );
  }

  static String? _nullable(String value) {
    final text = value.trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }
}
