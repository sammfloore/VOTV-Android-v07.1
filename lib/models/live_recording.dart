enum LiveRecordingStatus {
  recording,
  completed,
  interrupted,
  failed,
}

class LiveRecording {
  const LiveRecording({
    required this.id,
    required this.sourceChannelId,
    required this.title,
    required this.channelTitle,
    required this.posterUrl,
    required this.localPath,
    required this.startedAt,
    required this.endedAt,
    required this.durationSeconds,
    required this.sizeBytes,
    required this.status,
    required this.errorMessage,
    required this.maxDurationMinutes,
  });

  final String id;
  final String sourceChannelId;
  final String title;
  final String channelTitle;
  final String posterUrl;
  final String localPath;
  final int startedAt;
  final int endedAt;
  final int durationSeconds;
  final int sizeBytes;
  final LiveRecordingStatus status;
  final String errorMessage;
  final int maxDurationMinutes;

  bool get isActive => status == LiveRecordingStatus.recording;
  bool get canPlay =>
      !isActive && localPath.trim().isNotEmpty && sizeBytes >= 1024;
  DateTime get startedDate =>
      DateTime.fromMillisecondsSinceEpoch(startedAt, isUtc: false);

  factory LiveRecording.fromMap(Map<String, dynamic> map) {
    final rawStatus = '${map['status'] ?? ''}'.trim();
    final status = LiveRecordingStatus.values.firstWhere(
      (entry) => entry.name == rawStatus,
      orElse: () => LiveRecordingStatus.interrupted,
    );
    return LiveRecording(
      id: '${map['id'] ?? ''}',
      sourceChannelId: '${map['sourceChannelId'] ?? ''}',
      title: '${map['title'] ?? 'Grabación'}',
      channelTitle: '${map['channelTitle'] ?? 'Canal en vivo'}',
      posterUrl: '${map['posterUrl'] ?? ''}',
      localPath: '${map['localPath'] ?? ''}',
      startedAt: _asInt(map['startedAt']),
      endedAt: _asInt(map['endedAt']),
      durationSeconds: _asInt(map['durationSeconds']),
      sizeBytes: _asInt(map['sizeBytes']),
      status: status,
      errorMessage: '${map['errorMessage'] ?? ''}',
      maxDurationMinutes: _asInt(map['maxDurationMinutes']),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'sourceChannelId': sourceChannelId,
        'title': title,
        'channelTitle': channelTitle,
        'posterUrl': posterUrl,
        'localPath': localPath,
        'startedAt': startedAt,
        'endedAt': endedAt,
        'durationSeconds': durationSeconds,
        'sizeBytes': sizeBytes,
        'status': status.name,
        'errorMessage': errorMessage,
        'maxDurationMinutes': maxDurationMinutes,
      };
}

class RecordingCapability {
  const RecordingCapability({
    required this.supported,
    required this.isTelevision,
    required this.availableBytes,
    required this.minimumRequiredBytes,
    required this.reserveBytes,
    required this.notificationPermissionGranted,
    required this.reason,
  });

  const RecordingCapability.unavailable([this.reason = 'No disponible'])
      : supported = false,
        isTelevision = false,
        availableBytes = 0,
        minimumRequiredBytes = 0,
        reserveBytes = 0,
        notificationPermissionGranted = true;

  final bool supported;
  final bool isTelevision;
  final int availableBytes;
  final int minimumRequiredBytes;
  final int reserveBytes;
  final bool notificationPermissionGranted;
  final String reason;

  factory RecordingCapability.fromMap(Map<String, dynamic> map) {
    return RecordingCapability(
      supported: map['supported'] == true,
      isTelevision: map['isTelevision'] == true,
      availableBytes: _asInt(map['availableBytes']),
      minimumRequiredBytes: _asInt(map['minimumRequiredBytes']),
      reserveBytes: _asInt(map['reserveBytes']),
      notificationPermissionGranted:
          map['notificationPermissionGranted'] != false,
      reason: '${map['reason'] ?? ''}',
    );
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
