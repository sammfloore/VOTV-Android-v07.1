import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/offline_download.dart';

class DownloadService {
  DownloadService();

  static const _storeKey = 'avo_offline_downloads_v2';
  static const _legacyStoreKey = 'avo_offline_downloads_v1';
  static const _directoryName = 'avo_tv_offline';
  static const _groupName = 'avo_tv_media';
  static const _headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 AVO-TV/0.5',
    'Accept': '*/*',
  };

  final FileDownloader _downloader = FileDownloader();
  final Map<String, _DownloadJob> _jobs = {};
  final Map<String, String> _taskToJob = {};
  StreamSubscription<TaskUpdate>? _updatesSubscription;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _updatesSubscription = _downloader.updates.listen(_handleUpdate);
    await _downloader.start(
      doTrackTasks: true,
      markDownloadedComplete: true,
      doRescheduleKilledTasks: true,
    );
    await _downloader.resumeFromBackground();
    await _recoverCompletedDownloads();
  }

  Future<void> _recoverCompletedDownloads() async {
    try {
      final records = await _downloader.database.allRecordsWithStatus(
        TaskStatus.complete,
        group: _groupName,
      );
      for (final record in records) {
        await _recoverTaskFile(record.task);
      }
    } catch (_) {
      // The sidecar and preference scan still recovers normal completed files.
    }
  }

  Future<void> _recoverTaskFile(Task task) async {
    try {
      final decoded = jsonDecode(task.metaData);
      if (decoded is! Map) return;
      final meta = _DownloadMeta.fromMap(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
      if (meta.id.isEmpty || meta.filename.isEmpty) return;
      final path = await task.filePath();
      final file = File(path);
      if (!await file.exists() || await file.length() < 1024) return;
      await _writeSidecar(meta.copyWith(completed: true));
    } catch (_) {
      // Ignore records from another app version or malformed metadata.
    }
  }

  Future<List<OfflineDownload>> refreshFromBackground() async {
    await initialize();
    await _downloader.resumeFromBackground();
    await _recoverCompletedDownloads();
    return load();
  }

  Future<List<OfflineDownload>> load() async {
    await initialize();
    final itemsById = <String, OfflineDownload>{};
    final prefs = await SharedPreferences.getInstance();

    for (final key in const [_storeKey, _legacyStoreKey]) {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        for (final value in decoded) {
          if (value is! Map) continue;
          final item = OfflineDownload.fromMap(
            value.map((key, value) => MapEntry('$key', value)),
          );
          if (item.id.isEmpty || item.localPath.isEmpty) continue;
          if (await File(item.localPath).exists()) itemsById[item.id] = item;
        }
      } catch (_) {
        // Ignore a damaged legacy record and rebuild from sidecar files.
      }
    }

    final directory = await _offlineDirectory();
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.endsWith('.avo.json')) continue;
        try {
          final decoded = jsonDecode(await entity.readAsString());
          if (decoded is! Map) continue;
          final meta = _DownloadMeta.fromMap(
            decoded.map((key, value) => MapEntry('$key', value)),
          );
          if (!meta.completed) continue;
          final mediaFile = File(
            '${directory.path}${Platform.pathSeparator}${meta.filename}',
          );
          if (!await mediaFile.exists()) continue;
          final size = await mediaFile.length();
          if (size < 1024) continue;
          itemsById[meta.id] = OfflineDownload(
            id: meta.id,
            sourceMediaId: meta.sourceMediaId,
            title: meta.title,
            subtitle: meta.subtitle,
            posterUrl: meta.posterUrl,
            localPath: mediaFile.path,
            downloadedAt: meta.createdAt,
            sizeBytes: size,
            episodeId: meta.episodeId,
          );
        } catch (_) {
          // A sidecar can be ignored without affecting other downloads.
        }
      }
    }

    final items = itemsById.values.toList()
      ..sort((a, b) => b.downloadedAt.compareTo(a.downloadedAt));
    await _save(items);
    return items;
  }

  Future<OfflineDownload> download({
    required String id,
    required String sourceMediaId,
    required String title,
    required String subtitle,
    required String posterUrl,
    required List<String> urls,
    String? episodeId,
    required void Function(double progress) onProgress,
  }) async {
    await initialize();
    if (_jobs.containsKey(id)) {
      throw const DownloadException('Este contenido ya se está descargando.');
    }

    final candidates = urls
        .map((value) => value.trim())
        .where(_isDownloadableUrl)
        .toSet()
        .toList(growable: false);
    if (candidates.isEmpty) {
      throw const DownloadException(
        'Este contenido no ofrece un archivo directo compatible para descargar.',
      );
    }

    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final extension = _extensionFor(candidates.first);
    final filename = '$safeId.$extension';
    final meta = _DownloadMeta(
      id: id,
      sourceMediaId: sourceMediaId,
      title: title,
      subtitle: subtitle,
      posterUrl: posterUrl,
      filename: filename,
      episodeId: episodeId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _writeSidecar(meta);

    final completer = Completer<OfflineDownload>();
    final job = _DownloadJob(
      id: id,
      candidates: candidates,
      meta: meta,
      onProgress: onProgress,
      completer: completer,
    );
    _jobs[id] = job;

    final enqueued = await _enqueue(job);
    if (!enqueued) {
      _jobs.remove(id);
      throw const DownloadException(
        'Android no pudo iniciar la descarga en segundo plano.',
      );
    }
    return completer.future;
  }

  Future<bool> _enqueue(_DownloadJob job) async {
    if (job.candidateIndex >= job.candidates.length) return false;
    final url = job.candidates[job.candidateIndex];
    final taskId = '${job.id}__${job.attemptNumber++}';
    job.currentTaskId = taskId;
    _taskToJob[taskId] = job.id;

    final task = job.tryParallel
        ? ParallelDownloadTask(
            taskId: taskId,
            url: url,
            chunks: 4,
            filename: job.meta.filename,
            headers: _headers,
            directory: _directoryName,
            baseDirectory: BaseDirectory.applicationSupport,
            group: _groupName,
            updates: Updates.statusAndProgress,
            retries: 3,
            allowPause: true,
            priority: 0,
            metaData: jsonEncode(job.meta.toMap()),
            displayName: job.meta.title,
          )
        : DownloadTask(
            taskId: taskId,
            url: url,
            filename: job.meta.filename,
            headers: _headers,
            directory: _directoryName,
            baseDirectory: BaseDirectory.applicationSupport,
            group: _groupName,
            updates: Updates.statusAndProgress,
            retries: 3,
            allowPause: true,
            priority: 0,
            metaData: jsonEncode(job.meta.toMap()),
            displayName: job.meta.title,
          );
    return _downloader.enqueue(task);
  }

  Future<void> _handleUpdate(TaskUpdate update) async {
    final jobId = _taskToJob[update.task.taskId];
    if (jobId == null) {
      if (update is TaskStatusUpdate &&
          update.status == TaskStatus.complete) {
        await _recoverTaskFile(update.task);
      }
      return;
    }
    final job = _jobs[jobId];
    if (job == null) return;

    if (update is TaskProgressUpdate) {
      if (update.progress >= 0 && update.progress <= 1) {
        job.onProgress(update.progress);
      }
      return;
    }

    if (update is! TaskStatusUpdate) return;
    if (update.status == TaskStatus.complete) {
      await _completeJob(job, update.task);
      return;
    }
    if (update.status == TaskStatus.canceled) {
      _finishWithError(job, const DownloadException('La descarga fue cancelada.'));
      return;
    }
    if (update.status == TaskStatus.failed ||
        update.status == TaskStatus.notFound) {
      await _retryOrFail(job);
    }
  }

  Future<void> _completeJob(_DownloadJob job, Task task) async {
    try {
      final path = await task.filePath();
      final file = File(path);
      if (!await file.exists() || await file.length() < 1024) {
        await _retryOrFail(job);
        return;
      }
      await _writeSidecar(job.meta.copyWith(completed: true));
      final item = OfflineDownload(
        id: job.meta.id,
        sourceMediaId: job.meta.sourceMediaId,
        title: job.meta.title,
        subtitle: job.meta.subtitle,
        posterUrl: job.meta.posterUrl,
        localPath: file.path,
        downloadedAt: DateTime.now().millisecondsSinceEpoch,
        sizeBytes: await file.length(),
        episodeId: job.meta.episodeId,
      );
      final existing = await load();
      for (final previous in existing.where((entry) => entry.id == item.id)) {
        if (previous.localPath != item.localPath) {
          final old = File(previous.localPath);
          if (await old.exists()) await old.delete();
        }
      }
      await _save([item, ...existing.where((entry) => entry.id != item.id)]);
      job.onProgress(1);
      if (!job.completer.isCompleted) job.completer.complete(item);
      _cleanJob(job);
    } catch (_) {
      await _retryOrFail(job);
    }
  }

  Future<void> _retryOrFail(_DownloadJob job) async {
    if (job.tryParallel) {
      job.tryParallel = false;
    } else {
      job.tryParallel = true;
      job.candidateIndex++;
    }
    if (job.candidateIndex < job.candidates.length && await _enqueue(job)) return;
    _finishWithError(
      job,
      const DownloadException(
        'No se pudo descargar este contenido. El servidor no permitió completar el archivo.',
      ),
    );
  }

  void _finishWithError(_DownloadJob job, DownloadException error) {
    if (!job.completer.isCompleted) job.completer.completeError(error);
    _cleanJob(job);
    unawaited(_cleanupIncomplete(job));
  }

  Future<void> _cleanupIncomplete(_DownloadJob job) async {
    try {
      final directory = await _offlineDirectory();
      final media = File(
        '${directory.path}${Platform.pathSeparator}${job.meta.filename}',
      );
      if (await media.exists()) await media.delete();
      final sidecar = await _sidecarFile(job.meta.id);
      if (await sidecar.exists()) await sidecar.delete();
    } catch (_) {
      // Cleanup is best-effort and must not hide the original download error.
    }
  }

  void _cleanJob(_DownloadJob job) {
    _jobs.remove(job.id);
    _taskToJob.removeWhere((_, value) => value == job.id);
  }

  Future<void> remove(OfflineDownload item) async {
    final file = File(item.localPath);
    if (await file.exists()) await file.delete();
    final sidecar = await _sidecarFile(item.id);
    if (await sidecar.exists()) await sidecar.delete();
    final existing = await load();
    await _save(existing.where((entry) => entry.id != item.id).toList());
  }

  void cancel(String id) {
    final taskId = _jobs[id]?.currentTaskId;
    if (taskId != null) unawaited(_downloader.cancelTaskWithId(taskId));
  }

  bool _isDownloadableUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    return !uri.path.toLowerCase().endsWith('.m3u8');
  }

  String _extensionFor(String url) {
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last.toLowerCase()
        : '';
    final match = RegExp(r'\.([a-z0-9]{2,5})$').firstMatch(last);
    final extension = match?.group(1) ?? 'mp4';
    const allowed = {'mp4', 'mkv', 'avi', 'mov', 'webm', 'ts', 'm4v'};
    return allowed.contains(extension) ? extension : 'mp4';
  }

  Future<Directory> _offlineDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}$_directoryName',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<File> _sidecarFile(String id) async {
    final directory = await _offlineDirectory();
    final safeId = id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return File('${directory.path}${Platform.pathSeparator}$safeId.avo.json');
  }

  Future<void> _writeSidecar(_DownloadMeta meta) async {
    final file = await _sidecarFile(meta.id);
    await file.writeAsString(jsonEncode(meta.toMap()), flush: true);
  }

  Future<void> _save(List<OfflineDownload> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storeKey,
      jsonEncode(items.map((item) => item.toMap()).toList()),
    );
  }

  void dispose() {
    unawaited(_updatesSubscription?.cancel());
    // Native downloads are intentionally not canceled here. Android continues
    // them through WorkManager when the application moves to the background.
  }
}

class _DownloadJob {
  _DownloadJob({
    required this.id,
    required this.candidates,
    required this.meta,
    required this.onProgress,
    required this.completer,
  });

  final String id;
  final List<String> candidates;
  final _DownloadMeta meta;
  final void Function(double progress) onProgress;
  final Completer<OfflineDownload> completer;
  int candidateIndex = 0;
  int attemptNumber = 0;
  bool tryParallel = true;
  String? currentTaskId;
}

class _DownloadMeta {
  const _DownloadMeta({
    required this.id,
    required this.sourceMediaId,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    required this.filename,
    required this.createdAt,
    this.episodeId,
    this.completed = false,
  });

  final String id;
  final String sourceMediaId;
  final String title;
  final String subtitle;
  final String posterUrl;
  final String filename;
  final int createdAt;
  final String? episodeId;
  final bool completed;

  _DownloadMeta copyWith({bool? completed}) => _DownloadMeta(
        id: id,
        sourceMediaId: sourceMediaId,
        title: title,
        subtitle: subtitle,
        posterUrl: posterUrl,
        filename: filename,
        createdAt: createdAt,
        episodeId: episodeId,
        completed: completed ?? this.completed,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'sourceMediaId': sourceMediaId,
        'title': title,
        'subtitle': subtitle,
        'posterUrl': posterUrl,
        'filename': filename,
        'createdAt': createdAt,
        'episodeId': episodeId,
        'completed': completed,
      };

  factory _DownloadMeta.fromMap(Map<String, dynamic> map) => _DownloadMeta(
        id: '${map['id'] ?? ''}',
        sourceMediaId: '${map['sourceMediaId'] ?? ''}',
        title: '${map['title'] ?? ''}',
        subtitle: '${map['subtitle'] ?? ''}',
        posterUrl: '${map['posterUrl'] ?? ''}',
        filename: '${map['filename'] ?? ''}',
        createdAt: int.tryParse('${map['createdAt'] ?? 0}') ??
            DateTime.now().millisecondsSinceEpoch,
        episodeId: _nullable('${map['episodeId'] ?? ''}'),
        completed: map['completed'] == true || '${map['completed']}' == 'true',
      );

  static String? _nullable(String value) {
    final text = value.trim();
    return text.isEmpty || text == 'null' ? null : text;
  }
}

class DownloadException implements Exception {
  const DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}
