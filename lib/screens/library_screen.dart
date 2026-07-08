import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../models/offline_download.dart';
import '../models/player_launch_payload.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../widgets/media_row.dart';
import '../widgets/network_art.dart';
import 'activity_screen.dart';
import 'details_screen.dart';
import 'playback_settings_screen.dart';
import 'recordings_screen.dart';
import 'video_player_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final empty = state.myList.isEmpty &&
            state.continueWatching.isEmpty &&
            state.downloads.isEmpty &&
            state.recordings.isEmpty;
        return CustomScrollView(
          slivers: [
            SliverAppBar.large(
              title: const Text('Mi espacio'),
              backgroundColor: const Color(0xFF080A0D),
              actions: [
                IconButton(
                  tooltip: 'Configuración de reproducción',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlaybackSettingsScreen(state: state),
                    ),
                  ),
                  icon: const Icon(Icons.settings_rounded),
                ),
                IconButton(
                  tooltip: 'Mi actividad',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ActivityScreen(state: state),
                    ),
                  ),
                  icon: const Icon(Icons.history_rounded),
                ),
                if (!state.isDemo)
                  IconButton(
                    tooltip: 'Actualizar catálogo',
                    onPressed: state.isRefreshingCatalog
                        ? null
                        : () => _refreshCatalog(context),
                    icon: state.isRefreshingCatalog
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: () => _confirmLogout(context),
                  icon: const Icon(Icons.logout_rounded),
                ),
                const SizedBox(width: 8),
              ],
            ),
            SliverToBoxAdapter(
              child: _RecordingsEntryCard(state: state),
            ),
            if (state.catalogMessage != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.055),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(
                            state.offlineMode
                                ? Icons.cloud_off_rounded
                                : Icons.info_outline_rounded,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(state.catalogMessage!)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (state.downloads.isNotEmpty)
              SliverToBoxAdapter(
                child: _DownloadsSection(state: state),
              ),
            if (empty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bookmarks_outlined,
                          size: 68,
                          color: Colors.white.withValues(alpha: 0.34),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Tu espacio está listo',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Agrega títulos a Mi lista, comienza a ver algo o descarga contenido para verlo sin conexión.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.58),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              if (state.myList.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: 'Mi lista',
                    items: state.myList,
                    state: state,
                    onItemTap: (item) => _open(context, item),
                  ),
                ),
              if (state.continueWatching.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: 'Continuar viendo',
                    items: state.continueWatching,
                    state: state,
                    showProgress: true,
                    showContinueMenu: true,
                    onItemTap: (item) => _open(context, item),
                  ),
                ),
              if (state.recommendations.isNotEmpty)
                SliverToBoxAdapter(
                  child: MediaRow(
                    title: 'Basado en tu actividad',
                    items: state.recommendations,
                    state: state,
                    onItemTap: (item) => _open(context, item),
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        );
      },
    );
  }

  Future<void> _refreshCatalog(BuildContext context) async {
    final ok = await state.refreshCatalog();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.catalogMessage ??
              (ok ? 'Catálogo actualizado.' : 'No se pudo actualizar.'),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'La aplicación dejará de iniciar automáticamente. Mi lista, progreso y descargas locales no se borrarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.signOut();
  }

  void _open(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailsScreen(item: item, state: state),
      ),
    );
  }
}


class _RecordingsEntryCard extends StatelessWidget {
  const _RecordingsEntryCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final active = state.activeRecording;
    final capability = state.recordingCapability;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Material(
        color: active == null
            ? Colors.white.withValues(alpha: 0.055)
            : Colors.redAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RecordingsScreen(state: state),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  active == null
                      ? Icons.video_file_outlined
                      : Icons.fiber_manual_record_rounded,
                  color: active == null ? null : Colors.redAccent,
                  size: 30,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Mis grabaciones',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active != null
                            ? 'Grabando ahora: ${active.title}'
                            : state.recordings.isNotEmpty
                                ? '${state.recordings.length} grabaciones guardadas'
                                : capability.supported
                                    ? 'Graba televisión en vivo y sigue usando AVO TV'
                                    : capability.reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadsSection extends StatelessWidget {
  const _DownloadsSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Descargas',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 5),
          Text(
            '${state.downloads.length} guardadas en esta aplicación',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 14),
          ...state.downloads.map(
            (download) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DownloadTile(
                download: download,
                onPlay: () => _play(context, download),
                onDelete: () => _delete(context, download),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _play(BuildContext context, OfflineDownload download) async {
    final source = state.findById(download.sourceMediaId);
    final initialProgress = source == null
        ? 0.0
        : download.isEpisode
            ? state.episodeProgress(download.episodeId!)
            : state.progressFor(source);
    final opened = await PlatformService.openPlayer(
      PlayerLaunchPayload(
        title: download.title,
        subtitle: download.subtitle,
        urls: [download.localPath],
        isLive: false,
        initialProgress: initialProgress,
        mediaItem: source,
        progressEpisodeId: download.episodeId,
      ).toJson(),
    );
    if (opened || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          appState: state,
          title: download.title,
          subtitle: download.subtitle,
          urls: [download.localPath],
          isLive: false,
          initialProgress: initialProgress,
          onProgress: source == null
              ? null
              : (value) => state.savePlaybackProgress(
                    source,
                    value,
                    episodeId: download.episodeId,
                  ),
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    OfflineDownload download,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar descarga'),
        content: Text('¿Eliminar “${download.title}” de este dispositivo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.removeDownload(download);
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    required this.download,
    required this.onPlay,
    required this.onDelete,
  });

  final OfflineDownload download;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: NetworkArt(
                    url: download.posterUrl,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      download.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      download.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatBytes(download.sizeBytes),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Eliminar descarga',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              IconButton.filled(
                tooltip: 'Reproducir sin conexión',
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
