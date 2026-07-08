import 'package:flutter/material.dart';

import 'core/app_theme.dart';
import 'models/player_launch_payload.dart';
import 'screens/video_player_screen.dart';
import 'services/platform_service.dart';
import 'state/app_state.dart';

class AvoPlayerApp extends StatefulWidget {
  const AvoPlayerApp({super.key});

  @override
  State<AvoPlayerApp> createState() => _AvoPlayerAppState();
}

class _AvoPlayerAppState extends State<AvoPlayerApp> {
  final AppState _state = AppState();
  PlayerLaunchPayload? _payload;
  String? _error;
  GlobalKey<VideoPlayerScreenState> _playerKey =
      GlobalKey<VideoPlayerScreenState>();
  bool _replacementRunning = false;
  String? _pendingReplacement;

  @override
  void initState() {
    super.initState();
    PlatformService.setPlayerReplacementHandler(
      owner: this,
      onReplace: _replacePayload,
    );
    _load();
  }

  Future<void> _replacePayload(String rawPayload) async {
    _pendingReplacement = rawPayload;
    if (_replacementRunning) return;
    _replacementRunning = true;
    try {
      while (_pendingReplacement != null) {
        final nextPayload = _pendingReplacement!;
        _pendingReplacement = null;
        await _applyReplacement(nextPayload);
      }
    } finally {
      _replacementRunning = false;
    }
  }

  Future<void> _applyReplacement(String rawPayload) async {
    try {
      final payload = PlayerLaunchPayload.fromJson(rawPayload);
      await _playerKey.currentState?.prepareForReplacement();
      if (!mounted) return;
      setState(() {
        _payload = payload;
        _playerKey = GlobalKey<VideoPlayerScreenState>();
        _error = null;
      });
      await WidgetsBinding.instance.endOfFrame;
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo cambiar de canal: $error');
    }
  }

  Future<void> _load() async {
    try {
      final rawPayload = await PlatformService.getPlayerPayload();
      if (rawPayload == null || rawPayload.trim().isEmpty) {
        throw const FormatException('No se recibieron los datos del video.');
      }
      final payload = PlayerLaunchPayload.fromJson(rawPayload);
      await _state.initializePlaybackOnly();
      if (!mounted) return;
      setState(() => _payload = payload);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo abrir el reproductor: $error');
    }
  }

  @override
  void dispose() {
    PlatformService.clearPlayerReplacementHandler(owner: this);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AVO TV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    final error = _error;
    if (error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 58),
                const SizedBox(height: 16),
                Text(error, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: PlatformService.closePictureInPictureActivity,
                  child: const Text('Regresar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final payload = _payload;
    if (payload == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final item = payload.mediaItem;
    final details = payload.seriesDetails;
    final episodes = payload.episodes
        .map(
          (entry) => PlayerEpisode(
            episode: entry.episode,
            urls: entry.urls,
            initialProgress: item == null
                ? entry.initialProgress
                : _state.episodeProgress(entry.episode.id),
            previewImageUrl: entry.previewImageUrl,
          ),
        )
        .toList(growable: false);
    final initialProgress = item == null
        ? payload.initialProgress
        : payload.progressEpisodeId != null
            ? _state.episodeProgress(payload.progressEpisodeId!)
            : _state.progressFor(item);

    return VideoPlayerScreen(
      key: _playerKey,
      appState: _state,
      title: payload.title,
      subtitle: payload.subtitle,
      urls: payload.urls,
      isLive: payload.isLive,
      initialProgress: initialProgress,
      previewImageUrl: payload.previewImageUrl,
      episodes: episodes,
      initialEpisodeId: payload.initialEpisodeId,
      openedInPlayerActivity: true,
      liveChannelId: payload.isLive ? item?.id : null,
      onProgress: item == null || item.isLive
          ? null
          : (value) => _state.savePlaybackProgress(
                item,
                value,
                episodeId: payload.progressEpisodeId,
              ),
      onEpisodeStarted: item == null || details == null
          ? null
          : (episodeId) async {
              final selected = details.findEpisode(episodeId);
              if (selected != null) {
                await _state.markEpisodeStarted(item, selected);
              }
            },
      onEpisodeProgress: item == null || details == null
          ? null
          : (episodeId, value) async {
              final selected = details.findEpisode(episodeId);
              if (selected != null) {
                await _state.saveSeriesEpisodeProgress(
                  item,
                  details,
                  selected,
                  value,
                );
              }
            },
    );
  }
}
