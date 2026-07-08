import 'package:flutter/material.dart';

import '../models/live_recording.dart';
import '../models/player_launch_payload.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../widgets/network_art.dart';
import 'video_player_screen.dart';

class RecordingsScreen extends StatefulWidget {
  const RecordingsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    await widget.state.refreshRecordings();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis grabaciones'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _refreshing ? null : _refresh,
            icon: _refreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.state,
        builder: (context, _) {
          final recordings = widget.state.recordings;
          final capability = widget.state.recordingCapability;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: recordings.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(28),
                    children: [
                      const SizedBox(height: 80),
                      Icon(
                        Icons.video_file_outlined,
                        size: 76,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Todavía no hay grabaciones',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        capability.supported
                            ? 'Abre un canal en vivo y pulsa Grabar. La grabación continuará aunque veas otro contenido o salgas de AVO TV.'
                            : capability.reason,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          height: 1.45,
                          color: Colors.white.withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
                    children: [
                      _StorageSummary(capability: capability),
                      const SizedBox(height: 16),
                      ...recordings.map(
                        (recording) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RecordingCard(
                            recording: recording,
                            onPlay: recording.canPlay
                                ? () => _play(recording)
                                : null,
                            onStop: recording.isActive
                                ? () => _stop(recording)
                                : null,
                            onDelete: recording.isActive
                                ? null
                                : () => _delete(recording),
                          ),
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Future<void> _play(LiveRecording recording) async {
    final opened = await PlatformService.openPlayer(
      PlayerLaunchPayload(
        title: recording.title,
        subtitle: '${recording.channelTitle} • Grabación local',
        urls: [recording.localPath],
        isLive: false,
        previewImageUrl: recording.posterUrl,
      ).toJson(),
    );
    if (opened || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          appState: widget.state,
          title: recording.title,
          subtitle: '${recording.channelTitle} • Grabación local',
          urls: [recording.localPath],
          isLive: false,
          previewImageUrl: recording.posterUrl,
        ),
      ),
    );
  }

  Future<void> _stop(LiveRecording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detener grabación'),
        content: Text(
          '¿Deseas finalizar “${recording.title}”? El archivo quedará guardado en Mis grabaciones.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continuar grabando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Detener'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await widget.state.stopLiveRecording();
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _delete(LiveRecording recording) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar grabación'),
        content: Text(
          'Se eliminará permanentemente “${recording.title}” de este dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed = await widget.state.deleteLiveRecording(recording);
    if (!mounted || removed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No se pudo eliminar la grabación.')),
    );
  }
}

class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.capability});

  final RecordingCapability capability;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              capability.supported
                  ? Icons.storage_rounded
                  : Icons.sd_storage_outlined,
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    capability.supported
                        ? '${_formatBytes(capability.availableBytes)} disponibles'
                        : 'Grabación no disponible',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    capability.supported
                        ? 'Los videos se guardan de forma privada dentro de AVO TV.'
                        : capability.reason,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({
    required this.recording,
    required this.onPlay,
    required this.onStop,
    required this.onDelete,
  });

  final LiveRecording recording;
  final VoidCallback? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final status = switch (recording.status) {
      LiveRecordingStatus.recording => 'GRABANDO AHORA',
      LiveRecordingStatus.completed => 'FINALIZADA',
      LiveRecordingStatus.interrupted => 'INTERRUMPIDA',
      LiveRecordingStatus.failed => 'NO COMPLETADA',
    };
    final statusColor = switch (recording.status) {
      LiveRecordingStatus.recording => Colors.redAccent,
      LiveRecordingStatus.completed => Colors.greenAccent,
      _ => Colors.orangeAccent,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF12161B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: recording.isActive
              ? Colors.redAccent.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 116,
              height: 78,
              child: NetworkArt(
                url: recording.posterUrl,
                fit: BoxFit.contain,
                borderRadius: BorderRadius.circular(14),
                fallbackLabel: recording.channelTitle,
                live: true,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    recording.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    recording.channelTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(
                        _formatDate(recording.startedDate),
                        style: _metaStyle,
                      ),
                      Text(
                        _formatDuration(recording.durationSeconds),
                        style: _metaStyle,
                      ),
                      Text(
                        _formatBytes(recording.sizeBytes),
                        style: _metaStyle,
                      ),
                    ],
                  ),
                  if (recording.errorMessage.trim().isNotEmpty) ...[
                    const SizedBox(height: 7),
                    Text(
                      recording.errorMessage,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.orangeAccent,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onStop != null)
                  IconButton.filled(
                    tooltip: 'Detener grabación',
                    onPressed: onStop,
                    icon: const Icon(Icons.stop_rounded),
                  ),
                if (onPlay != null)
                  IconButton.filled(
                    tooltip: 'Reproducir',
                    onPressed: onPlay,
                    icon: const Icon(Icons.play_arrow_rounded),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static final _metaStyle = TextStyle(
    color: Colors.white.withValues(alpha: 0.45),
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );
}

String _formatBytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String _formatDuration(int seconds) {
  final duration = Duration(seconds: seconds.clamp(0, 99999999).toInt());
  final hours = duration.inHours.toString().padLeft(2, '0');
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final secs = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$secs';
}

String _formatDate(DateTime date) {
  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  final day = date.day.toString().padLeft(2, '0');
  final month = months[date.month - 1];
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day $month ${date.year} · $hour:$minute';
}
