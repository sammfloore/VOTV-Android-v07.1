import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/series_details.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';

class PlayerEpisode {
  const PlayerEpisode({
    required this.episode,
    required this.urls,
    required this.initialProgress,
    this.previewImageUrl = '',
  });

  final EpisodeItem episode;
  final List<String> urls;
  final double initialProgress;
  final String previewImageUrl;
}

class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    super.key,
    required this.appState,
    required this.title,
    required this.urls,
    required this.isLive,
    this.subtitle,
    this.initialProgress = 0,
    this.onProgress,
    this.previewImageUrl = '',
    this.episodes = const [],
    this.initialEpisodeId,
    this.onEpisodeProgress,
    this.onEpisodeStarted,
    this.upNextTitle,
    this.onPlayUpNext,
    this.openedInPlayerActivity = false,
    this.liveChannelId,
  });

  final String title;
  final AppState appState;
  final String? subtitle;
  final List<String> urls;
  final bool isLive;
  final double initialProgress;
  final Future<void> Function(double progress)? onProgress;
  final String previewImageUrl;
  final List<PlayerEpisode> episodes;
  final String? initialEpisodeId;
  final Future<void> Function(String episodeId, double progress)?
      onEpisodeProgress;
  final Future<void> Function(String episodeId)? onEpisodeStarted;
  final String? upNextTitle;
  final Future<void> Function()? onPlayUpNext;
  final bool openedInPlayerActivity;
  final String? liveChannelId;

  @override
  State<VideoPlayerScreen> createState() => VideoPlayerScreenState();
}

class VideoPlayerScreenState extends State<VideoPlayerScreen>
    with WidgetsBindingObserver {
  static const _httpHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 AVO-TV/0.7.1',
    'Accept': '*/*',
  };

  late final Player _player;
  late final VideoController _videoController;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<int, Uint8List?> _previewCache = {};
  final Map<String, double> _episodeProgressOverrides = {};

  Timer? _controlsTimer;
  Timer? _saveTimer;
  Timer? _previewDebounce;
  Timer? _autoNextTimer;
  Timer? _sleepTimer;
  Timer? _gestureOverlayTimer;
  Timer? _stallTimer;
  Timer? _liveHealthTimer;
  bool _showControls = true;
  bool _loading = true;
  bool _locked = false;
  bool _playing = false;
  bool _buffering = false;
  bool _scrubbing = false;
  bool _completionHandled = false;
  bool _showUpNext = false;
  bool _switchingTrack = false;
  bool _seeking = false;
  bool _recoveringPlayback = false;
  bool _detectTimelineOriginAfterPlay = false;
  bool _gestureControlsBrightness = false;
  bool _inPictureInPicture = false;
  bool _allowRoutePop = false;
  bool _pipAttemptedWhileLeaving = false;
  bool _sleepAtEpisodeEnd = false;
  String? _error;
  int _activeUrlIndex = 0;
  String _activeResource = '';
  int _attemptedUrls = 0;
  int _episodeIndex = -1;
  int _autoNextSeconds = 0;
  Duration _rawPosition = Duration.zero;
  Duration _rawDuration = Duration.zero;
  Duration _timelineOrigin = Duration.zero;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _scrubPosition = Duration.zero;
  double _volume = 100;
  double _subtitleScale = 1;
  double _rate = 1;
  double _brightness = 0.5;
  double _lastSavedProgress = -1;
  Tracks _tracks = Tracks();
  Track _selectedTrack = Track();
  BoxFit _fit = BoxFit.contain;
  double? _aspectRatio;
  int _aspectIndex = 0;
  Uint8List? _previewBytes;
  double? _gestureOverlayValue;
  String? _gestureOverlayLabel;
  IconData _gestureOverlayIcon = Icons.volume_up_rounded;
  DateTime _lastPositionPaint = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ignoreProgressUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _playStartedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _seekGeneration = 0;
  final List<String> _candidateUrls = [];
  Duration? _pendingSeekTarget;
  Duration? _optimisticSeekTarget;
  bool _pendingSeekPersist = true;
  bool _pendingSeekShowFailure = true;
  bool _seekLoopActive = false;
  DateTime _suppressPositionUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _ignoreErrorsUntil = DateTime.fromMillisecondsSinceEpoch(0);
  Duration _lastAdvancingPosition = Duration.zero;
  DateTime _lastAdvanceAt = DateTime.fromMillisecondsSinceEpoch(0);
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  DateTime? _sleepDeadline;
  bool _preparingForReplacement = false;
  bool _playerDisposed = false;

  static const _aspectOptions = <({String label, BoxFit fit, double? ratio})>[
    (label: 'Ajustar', fit: BoxFit.contain, ratio: null),
    (label: 'Llenar', fit: BoxFit.cover, ratio: null),
    (label: 'Estirar', fit: BoxFit.fill, ratio: null),
    (label: '4:3', fit: BoxFit.contain, ratio: 4 / 3),
    (label: '16:9', fit: BoxFit.contain, ratio: 16 / 9),
  ];

  bool get _hasEpisodes => widget.episodes.isNotEmpty;
  PlayerEpisode? get _currentEpisode =>
      _episodeIndex >= 0 && _episodeIndex < widget.episodes.length
          ? widget.episodes[_episodeIndex]
          : null;
  List<String> get _activeUrls => _currentEpisode?.urls ?? widget.urls;
  double get _activeInitialProgress {
    final current = _currentEpisode;
    if (current == null) return widget.initialProgress;
    return _episodeProgressOverrides[current.episode.id] ??
        current.initialProgress;
  }
  String get _activePreviewImageUrl {
    final current = _currentEpisode;
    if (current != null && current.previewImageUrl.trim().isNotEmpty) {
      return current.previewImageUrl;
    }
    return widget.previewImageUrl;
  }
  String? get _activeSubtitle => _currentEpisode == null
      ? widget.subtitle
      : '${_currentEpisode!.episode.numberLabel} • ${_currentEpisode!.episode.title}';
  String get _aspectLabel => _aspectOptions[_aspectIndex].label;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _volume = widget.appState.playbackVolume;
    _subtitleScale = widget.appState.subtitleScale;
    if (_hasEpisodes) {
      final requested = widget.initialEpisodeId;
      final index = requested == null
          ? 0
          : widget.episodes.indexWhere(
              (entry) => entry.episode.id == requested,
            );
      _episodeIndex = index < 0 ? 0 : index;
      final id = _currentEpisode?.episode.id;
      if (id != null) unawaited(widget.onEpisodeStarted?.call(id));
    }
    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: (widget.isLive ? 32 : 64) * 1024 * 1024,
      ),
    );
    _videoController = VideoController(_player);
    PlatformService.setPictureInPictureHandlers(
      owner: this,
      onAction: _handlePictureInPictureAction,
      onModeChanged: _handlePictureInPictureModeChanged,
    );
    widget.appState.addListener(_handleAppStateChanged);
    _bindPlayerStreams();
    unawaited(_configureNetworkPlayback());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    unawaited(_loadBrightness());
    unawaited(_initialize());
    unawaited(_syncPictureInPictureConfiguration());
  }


  void _bindPlayerStreams() {
    _subscriptions.addAll([
      _player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => _playing = value);
        unawaited(_syncPictureInPictureConfiguration());
        if (value) {
          _lastAdvanceAt = DateTime.now();
          _scheduleControlsHide();
        }
      }),
      _player.stream.buffering.listen((value) {
        if (!mounted) return;
        setState(() => _buffering = value);
        if (value && !_loading && !_seeking) {
          _scheduleStallRecovery();
        } else if (!value) {
          _stallTimer?.cancel();
        }
      }),
      _player.stream.position.listen((value) {
        if (!mounted) return;
        final now = DateTime.now();

        if (_detectTimelineOriginAfterPlay &&
            _timelineOrigin == Duration.zero &&
            now.difference(_playStartedAt) <=
                const Duration(milliseconds: 850) &&
            value >= const Duration(seconds: 8) &&
            value <= const Duration(seconds: 30)) {
          // Algunos TS comienzan con una marca temporal distinta de cero. La
          // restamos visualmente sin ejecutar un seek adicional al arrancar.
          _timelineOrigin = value;
          _duration = _displayDurationFor(_rawDuration);
          _detectTimelineOriginAfterPlay = false;
        } else if (_detectTimelineOriginAfterPlay &&
            now.difference(_playStartedAt) >
                const Duration(milliseconds: 850)) {
          _detectTimelineOriginAfterPlay = false;
        }

        final display = _displayPositionFor(value);
        final optimistic = _optimisticSeekTarget;
        if (_seeking &&
            optimistic != null &&
            now.isBefore(_suppressPositionUntil) &&
            (display - optimistic).abs() > _seekTolerance()) {
          // No permitimos que posiciones viejas hagan brincar la barra hacia
          // atrás mientras el servidor todavía procesa el seek.
          return;
        }

        _rawPosition = value;
        _position = display;
        final advanceProbe = widget.isLive ? value : display;
        if (advanceProbe >
            _lastAdvancingPosition + const Duration(milliseconds: 450)) {
          _lastAdvancingPosition = advanceProbe;
          _lastAdvanceAt = now;
        }

        if (_showControls &&
            now.difference(_lastPositionPaint) >=
                const Duration(milliseconds: 300)) {
          _lastPositionPaint = now;
          setState(() {});
          }
        if (!widget.isLive &&
            _duration > Duration.zero &&
            _position >= _duration - const Duration(milliseconds: 900) &&
            !_completionHandled) {
          _completionHandled = true;
          unawaited(_persistProgress(forceValue: 1));
          if (_sleepAtEpisodeEnd) {
            _sleepAtEpisodeEnd = false;
            unawaited(_pauseForSleepTimer());
          } else if (_hasEpisodes && _episodeIndex + 1 < widget.episodes.length) {
            _startAutoNext();
          } else if (widget.onPlayUpNext != null) {
            setState(() => _showUpNext = true);
          }
        }
      }),
      _player.stream.duration.listen((value) {
        _rawDuration = value;
        final normalized = _displayDurationFor(value);
        if (mounted) setState(() => _duration = normalized);
      }),
      _player.stream.error.listen((message) {
        final now = DateTime.now();
        if (_loading ||
            _seeking ||
            _switchingTrack ||
            now.isBefore(_ignoreErrorsUntil)) {
          return;
        }
        if (widget.isLive) {
          unawaited(_recoverLivePlaybackAfterError(message));
        } else {
          unawaited(_recoverPlaybackAfterError(message));
        }
      }),
      _player.stream.volume.listen((value) {
        if (!mounted) return;
        final reported = value.clamp(0, 200).toDouble();
        if ((_volume - reported).abs() < 0.6 || reported > 100) {
          setState(() => _volume = reported);
        }
      }),
      _player.stream.rate.listen((value) {
        if (mounted) setState(() => _rate = value);
      }),
      _player.stream.tracks.listen((value) {
        if (mounted) setState(() => _tracks = value);
      }),
      _player.stream.track.listen((value) {
        if (mounted) setState(() => _selectedTrack = value);
      }),
    ]);
  }

  Future<void> _loadBrightness() async {
    try {
      final value = await ScreenBrightness.instance.application;
      if (mounted) setState(() => _brightness = value.clamp(0.05, 1).toDouble());
    } catch (_) {
      // Keep the current brightness if Android does not expose it.
    }
  }

  Future<void> _configureNetworkPlayback() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    final properties = widget.isLive
        ? const <String, String>{
            'cache': 'yes',
            'cache-on-disk': 'no',
            'cache-pause': 'no',
            'cache-pause-initial': 'no',
            'demuxer-seekable-cache': 'no',
            'demuxer-max-bytes': '16777216',
            'demuxer-max-back-bytes': '0',
            'demuxer-readahead-secs': '5',
            'network-timeout': '8',
            'cache-secs': '6',
          }
        : const <String, String>{
            'cache': 'yes',
            'cache-on-disk': 'no',
            'cache-pause': 'yes',
            'cache-pause-initial': 'yes',
            'cache-pause-wait': '1',
            'demuxer-seekable-cache': 'yes',
            'demuxer-max-bytes': '67108864',
            'demuxer-max-back-bytes': '16777216',
            'demuxer-readahead-secs': '25',
            'network-timeout': '15',
          };
    for (final entry in properties.entries) {
      try {
        await platform.setProperty(entry.key, entry.value);
      } catch (_) {
        // Una versión concreta de libmpv puede ignorar alguna opción sin
        // impedir que el reproductor funcione con sus valores predeterminados.
      }
    }
  }

  void _handleAppStateChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_syncPictureInPictureConfiguration());
  }

  bool get _hasNextEpisode =>
      _hasEpisodes && _episodeIndex + 1 < widget.episodes.length;

  Future<void> _syncPictureInPictureConfiguration() async {
    final enabled = widget.appState.pictureInPictureEnabled &&
        _error == null;
    await PlatformService.configurePictureInPicture(
      enabled: enabled,
      autoEnter: enabled &&
          widget.appState.pictureInPictureAutoEnter &&
          _playing &&
          !_loading,
      isPlaying: _playing,
      hasNext: _hasNextEpisode,
      title: widget.title,
      subtitle: _activeSubtitle ?? '',
    );
  }

  void _handlePictureInPictureModeChanged(bool isInPictureInPicture) {
    if (!mounted) return;
    setState(() {
      _inPictureInPicture = isInPictureInPicture;
      if (isInPictureInPicture) {
        _showControls = false;
        _locked = false;
      } else {
        _showControls = true;
      }
    });
    _pipAttemptedWhileLeaving = false;
    if (!isInPictureInPicture) _scheduleControlsHide();
  }

  Future<void> _handlePictureInPictureAction(String action) async {
    switch (action) {
      case 'toggle':
        await _togglePlayback();
        break;
      case 'next':
        if (_hasNextEpisode) await _switchEpisode(_episodeIndex + 1);
        break;
      case 'close':
        await _persistProgress();
        await _player.pause();
        await PlatformService.configurePictureInPicture(
          enabled: false,
          autoEnter: false,
          isPlaying: false,
          hasNext: false,
          title: widget.title,
          subtitle: _activeSubtitle ?? '',
        );
        await PlatformService.closePictureInPictureActivity();
        break;
    }
  }

  Future<void> _enterPictureInPictureManually() async {
    if (!widget.appState.pictureInPictureEnabled) {
      _notice(
        'Activa Picture-in-Picture en Mi espacio → Configuración de reproducción.',
      );
      return;
    }
    final supported = await PlatformService.isPictureInPictureSupported();
    if (!supported) {
      _notice('Picture-in-Picture requiere Android 8.0 o posterior.');
      return;
    }
    final allowed = await PlatformService.isPictureInPictureAllowed();
    if (!allowed) {
      await _showPictureInPicturePermissionDialog();
      return;
    }
    await _syncPictureInPictureConfiguration();
    final entered = await PlatformService.enterPictureInPicture();
    if (!entered) {
      _notice('Android no pudo abrir la ventana flotante en este momento.');
    }
  }

  Future<void> _showPictureInPicturePermissionDialog() async {
    if (!mounted) return;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permitir ventana flotante'),
        content: const Text(
          'Android tiene desactivado Picture-in-Picture para AVO TV. Abre los ajustes y permite esta función para continuar viendo el video al salir de la aplicación.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );
    if (openSettings == true) {
      await PlatformService.openPictureInPictureSettings();
    }
  }

  void _scheduleStallRecovery() {
    _stallTimer?.cancel();
    _stallTimer = Timer(Duration(seconds: widget.isLive ? 6 : 12), () {
      if (!mounted || !_buffering || _loading || _seeking) {
        return;
      }
      final stalledFor = DateTime.now().difference(_lastAdvanceAt);
      final limit = widget.isLive
          ? const Duration(seconds: 7)
          : const Duration(seconds: 10);
      if (stalledFor >= limit) {
        if (widget.isLive) {
          unawaited(_recoverLivePlaybackAfterError('live-buffering-timeout'));
        } else {
          unawaited(_recoverPlaybackAfterError('buffering-timeout'));
        }
      }
    });
  }

  Future<void> _initialize() async {
    _autoNextTimer?.cancel();
    _previewDebounce?.cancel();
    _stallTimer?.cancel();
    _liveHealthTimer?.cancel();
    _previewCache.clear();
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _attemptedUrls = 0;
        _rawPosition = Duration.zero;
        _rawDuration = Duration.zero;
        _timelineOrigin = Duration.zero;
        _position = Duration.zero;
        _duration = Duration.zero;
        _scrubbing = false;
        _seeking = false;
        _seekLoopActive = false;
        _pendingSeekTarget = null;
        _optimisticSeekTarget = null;
        _detectTimelineOriginAfterPlay = false;
        _ignoreProgressUntil = DateTime.fromMillisecondsSinceEpoch(0);
        _ignoreErrorsUntil = DateTime.fromMillisecondsSinceEpoch(0);
        _previewBytes = null;
        _completionHandled = false;
        _showUpNext = false;
        _autoNextSeconds = 0;
      });
    }

    _candidateUrls
      ..clear()
      ..addAll(
        _orderedCandidates(
          _activeUrls
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet()
              .toList(growable: false),
        ),
      );

    if (_candidateUrls.isEmpty) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Este contenido no incluye una dirección de reproducción.';
        });
      }
      return;
    }

    for (var index = 0; index < _candidateUrls.length; index++) {
      final resource = _candidateUrls[index];
      if (!_validResource(resource)) continue;
      _attemptedUrls++;
      final opened = await _openCandidate(index, resource);
      if (!opened) continue;

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
      _scheduleControlsHide();
      _saveTimer ??= Timer.periodic(
        const Duration(seconds: 5),
        (_) => unawaited(_persistProgress()),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = widget.isLive
          ? 'No se pudo abrir este canal después de probar $_attemptedUrls direcciones.'
          : 'No se pudo reproducir este contenido después de probar $_attemptedUrls direcciones.';
    });
  }

  Future<bool> _openCandidate(
    int index,
    String resource, {
    Duration? resumeAt,
  }) async {
    try {
      await _player.stop();
      _timelineOrigin = Duration.zero;
      _rawPosition = Duration.zero;
      _position = Duration.zero;
      _rawDuration = Duration.zero;
      _duration = Duration.zero;
      _lastAdvancingPosition = Duration.zero;
      _lastAdvanceAt = DateTime.now();
      _ignoreErrorsUntil = DateTime.now().add(const Duration(seconds: 3));

      final media = _mediaFor(resource);
      var reportedError = false;
      final errorSubscription = _player.stream.error.listen((_) {
        reportedError = true;
      });
      try {
        await _player.open(media, play: true);
        var ready = false;
        for (var attempt = 0; attempt < 60; attempt++) {
          if (reportedError) break;
          final state = _player.state;
          if (state.position > Duration.zero ||
              (state.playing &&
                  !state.buffering &&
                  (widget.isLive || state.duration > Duration.zero))) {
            ready = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        if (!ready) return false;
      } finally {
        await errorSubscription.cancel();
      }

      _activeUrlIndex = index;
      _activeResource = resource;
      await _applyStoredAudioPreferences();
      _playStartedAt = DateTime.now();
      _detectTimelineOriginAfterPlay = !widget.isLive &&
          (resumeAt ?? Duration.zero) == Duration.zero &&
          _activeInitialProgress < 0.01;

      if (widget.isLive) {
        _startLiveHealthMonitor();
      } else {
        await _loadVodDuration();
        final requested = resumeAt ?? _initialResumeTarget();
        if (requested > const Duration(seconds: 30)) {
          await _performSeek(
            requested,
            persistImmediately: false,
            showFailure: false,
          );
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  void _startLiveHealthMonitor() {
    if (!widget.isLive) return;
    _liveHealthTimer?.cancel();
    _liveHealthTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _loading || _seeking || _recoveringPlayback) return;
      if (!_playing || _activeResource.isEmpty) return;
      final stalledFor = DateTime.now().difference(_lastAdvanceAt);
      if (stalledFor >= const Duration(seconds: 18)) {
        unawaited(_recoverLivePlaybackAfterError('live-health-timeout'));
      }
    });
  }

  Future<void> _loadVodDuration() async {
    var duration = _player.state.duration;
    for (var attempt = 0; attempt < 24 && duration <= Duration.zero; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 125));
      duration = _player.state.duration;
    }
    _rawDuration = duration;
    _duration = _displayDurationFor(duration);
    _rawPosition = _player.state.position;
    _position = _displayPositionFor(_rawPosition);
  }

  Duration _initialResumeTarget() {
    if (_duration <= Duration.zero) return Duration.zero;
    final normalized = _activeInitialProgress.clamp(0.0, 1.0).toDouble();
    final target = Duration(
      milliseconds: (_duration.inMilliseconds * normalized).round(),
    );
    return target < const Duration(seconds: 30) ? Duration.zero : target;
  }

  bool _validResource(String resource) {
    final file = File(resource);
    if (file.existsSync()) return true;
    final uri = Uri.tryParse(resource);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Media _mediaFor(String resource) {
    final file = File(resource);
    if (file.existsSync()) return Media(file.uri.toString());
    return Media(resource, httpHeaders: _httpHeaders);
  }

  List<String> _orderedCandidates(List<String> candidates) {
    // La API ya entrega primero direct_source y después la extensión real del
    // catálogo. Alterar ese orden (por ejemplo, forzar MP4 antes que MKV/TS)
    // hacía probar enlaces inexistentes y provocaba cargas interminables.
    final local = <String>[];
    final remote = <String>[];
    for (final value in candidates) {
      if (File(value).existsSync()) {
        local.add(value);
      } else {
        remote.add(value);
      }
    }
    return <String>[...local, ...remote];
  }

  Duration _displayPositionFor(Duration raw) {
    if (widget.isLive || raw <= _timelineOrigin) return Duration.zero;
    return raw - _timelineOrigin;
  }

  Duration _displayDurationFor(Duration raw) {
    if (widget.isLive || raw <= _timelineOrigin) return raw;
    return raw - _timelineOrigin;
  }

  Duration _rawPositionFor(Duration display) {
    if (widget.isLive) return display;
    return _timelineOrigin + display;
  }

  Duration _seekTolerance() {
    final lower = _activeResource.toLowerCase().split('?').first;
    if (lower.endsWith('.ts') || lower.endsWith('.m3u8')) {
      return const Duration(seconds: 10);
    }
    return const Duration(seconds: 3);
  }

  Future<bool> _performSeek(
    Duration requested, {
    bool persistImmediately = true,
    bool showFailure = true,
  }) async {
    if (widget.isLive || _duration <= Duration.zero) return false;
    final target = Duration(
      milliseconds: requested.inMilliseconds
          .clamp(0, _duration.inMilliseconds)
          .toInt(),
    );

    _pendingSeekTarget = target;
    _pendingSeekPersist = persistImmediately;
    _pendingSeekShowFailure = showFailure;
    _optimisticSeekTarget = target;
    _suppressPositionUntil = DateTime.now().add(const Duration(seconds: 3));
    if (mounted) setState(() => _position = target);

    if (_seekLoopActive) return true;
    _seekLoopActive = true;
    var lastReached = false;
    if (mounted) setState(() => _seeking = true);

    try {
      while (_pendingSeekTarget != null) {
        final next = _pendingSeekTarget!;
        final persist = _pendingSeekPersist;
        final notifyFailure = _pendingSeekShowFailure;
        _pendingSeekTarget = null;
        lastReached = await _executeSeek(
          next,
          persistImmediately: persist,
          showFailure: notifyFailure,
        );
      }
      return lastReached;
    } finally {
      _seekLoopActive = false;
      _optimisticSeekTarget = null;
      if (mounted) setState(() => _seeking = false);
    }
  }

  Future<bool> _executeSeek(
    Duration target, {
    required bool persistImmediately,
    required bool showFailure,
  }) async {
    final generation = ++_seekGeneration;
    final rawTarget = _rawPositionFor(target);
    final wasPlaying = _player.state.playing;
    _ignoreProgressUntil = DateTime.now().add(const Duration(seconds: 5));
    _ignoreErrorsUntil = DateTime.now().add(const Duration(seconds: 4));
    _optimisticSeekTarget = target;
    _suppressPositionUntil = DateTime.now().add(const Duration(seconds: 3));

    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.seek(rawTarget, synchronized: false);
      } else {
        await _player.seek(rawTarget);
      }

      final reached = await _waitForSeekTarget(target, generation);
      if (wasPlaying && !_player.state.playing) {
        await _player.play();
      }

      _rawPosition = _player.state.position;
      final actual = _displayPositionFor(_rawPosition);
      if (reached || DateTime.now().isAfter(_suppressPositionUntil)) {
        _position = actual;
      }

      if (persistImmediately) {
        final savedPosition = reached ? actual : target;
        final value = savedPosition == Duration.zero
            ? 0.0
            : (savedPosition.inMilliseconds / _duration.inMilliseconds)
                .clamp(0.0, 1.0)
                .toDouble();
        await _saveProgressValue(value);
      }

      if (!reached && showFailure) {
        _notice(
          'El servidor hizo un salto aproximado. La reproducción continuará desde el punto disponible más cercano.',
        );
      }
      return reached;
    } catch (_) {
      if (wasPlaying && !_player.state.playing) {
        await _player.play();
      }
      if (showFailure) {
        _notice('No se pudo mover el video en este intento. Intenta de nuevo.');
      }
      return false;
    }
  }

  Future<bool> _waitForSeekTarget(Duration target, int generation) async {
    final tolerance = _seekTolerance();
    for (var attempt = 0; attempt < 36; attempt++) {
      if (generation != _seekGeneration) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final current = _displayPositionFor(_player.state.position);
      if ((current - target).abs() <= tolerance) {
        _rawPosition = _player.state.position;
        _position = current;
        return true;
      }
      if (!_player.state.buffering &&
          attempt >= 12 &&
          current != Duration.zero &&
          (current - target).abs() <= const Duration(seconds: 20)) {
        // Algunos transport streams solo permiten saltar al keyframe cercano.
        _rawPosition = _player.state.position;
        _position = current;
        return true;
      }
    }
    return false;
  }

  Future<void> _saveProgressValue(double value) async {
    _lastSavedProgress = value;
    final episode = _currentEpisode;
    if (episode != null && widget.onEpisodeProgress != null) {
      _episodeProgressOverrides[episode.episode.id] = value;
      await widget.onEpisodeProgress!(episode.episode.id, value);
    } else {
      await widget.onProgress?.call(value);
    }
  }

  Future<void> _recoverLivePlaybackAfterError(String message) async {
    if (_recoveringPlayback || !mounted || _activeResource.isEmpty) return;
    _recoveringPlayback = true;
    _stallTimer?.cancel();
    try {
      final before = _player.state.position;
      await _player.play();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final after = _player.state.position;
      if (_player.state.playing && after >= before && !_player.state.buffering) {
        return;
      }

      final order = <int>[
        _activeUrlIndex,
        for (var index = 0; index < _candidateUrls.length; index++)
          if (index != _activeUrlIndex) index,
      ];
      for (final index in order) {
        final resource = _candidateUrls[index];
        if (!_validResource(resource)) continue;
        final opened = await _openCandidate(index, resource);
        if (opened) {
          if (mounted) {
            setState(() {
              _error = null;
              _loading = false;
              _buffering = false;
            });
          }
          return;
        }
      }
      if (mounted) {
        setState(() {
          _error = 'La señal en vivo perdió conexión. Pulsa Reintentar o prueba otro canal.';
          _loading = false;
          _buffering = false;
        });
      }
    } finally {
      _recoveringPlayback = false;
    }
  }

  Future<void> _recoverPlaybackAfterError(String message) async {
    if (_recoveringPlayback || !mounted || _activeResource.isEmpty) return;
    _recoveringPlayback = true;
    _stallTimer?.cancel();
    final target = _position;
    try {
      final before = _player.state.position;
      await _player.play();
      await Future<void>.delayed(const Duration(seconds: 2));
      final after = _player.state.position;
      if (after > before + const Duration(milliseconds: 500)) return;

      final order = <int>[
        _activeUrlIndex,
        for (var index = 0; index < _candidateUrls.length; index++)
          if (index != _activeUrlIndex) index,
      ];
      for (final index in order) {
        final resource = _candidateUrls[index];
        if (!_validResource(resource)) continue;
        final opened = await _openCandidate(
          index,
          resource,
          resumeAt: target,
        );
        if (opened) {
          if (mounted) {
            setState(() {
              _error = null;
              _loading = false;
            });
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _error = 'La reproducción perdió conexión. Pulsa Reintentar para continuar.';
          _loading = false;
        });
      }
    } finally {
      _recoveringPlayback = false;
    }
  }

  void _toggleControls() {
    if (_locked) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleControlsHide();
  }

  void _scheduleControlsHide() {
    if (_locked || _scrubbing) return;
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _playing && !_locked && !_scrubbing) {
        setState(() => _showControls = false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_playing) {
      await _player.pause();
      _controlsTimer?.cancel();
      if (mounted) setState(() => _showControls = true);
    } else {
      await _player.play();
      _scheduleControlsHide();
    }
  }

  Future<void> _seekRelative(int seconds) async {
    if (widget.isLive || _duration <= Duration.zero) return;
    final base = _pendingSeekTarget ?? _optimisticSeekTarget ?? _position;
    final value = (base + Duration(seconds: seconds)).inMilliseconds;
    unawaited(
      _performSeek(
        Duration(
          milliseconds: value.clamp(0, _duration.inMilliseconds).toInt(),
        ),
      ),
    );
    _scheduleControlsHide();
  }

  Future<void> _persistProgress({double? forceValue}) async {
    if (widget.isLive || _duration <= Duration.zero) return;
    if (forceValue == null &&
        (_seeking || DateTime.now().isBefore(_ignoreProgressUntil))) {
      return;
    }
    final value = forceValue ??
        (_position.inMilliseconds / _duration.inMilliseconds)
            .clamp(0.0, 1.0)
            .toDouble();
    if (forceValue == null && (value - _lastSavedProgress).abs() < 0.005) {
      return;
    }
    await _saveProgressValue(value);
  }

  Future<void> _switchEpisode(int index) async {
    if (index < 0 || index >= widget.episodes.length || index == _episodeIndex) {
      return;
    }
    await _persistProgress();
    _autoNextTimer?.cancel();
    setState(() {
      _episodeIndex = index;
      _lastSavedProgress = -1;
    });
    final id = _currentEpisode!.episode.id;
    await widget.onEpisodeStarted?.call(id);
    await _initialize();
    await _syncPictureInPictureConfiguration();
  }

  void _startAutoNext() {
    _autoNextTimer?.cancel();
    setState(() => _autoNextSeconds = 10);
    _autoNextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      if (_autoNextSeconds <= 1) {
        timer.cancel();
        unawaited(_switchEpisode(_episodeIndex + 1));
      } else {
        setState(() => _autoNextSeconds--);
      }
    });
  }

  void _cancelAutoNext() {
    _autoNextTimer?.cancel();
    if (mounted) setState(() => _autoNextSeconds = 0);
  }

  Future<void> _showSleepTimerMenu() async {
    final selection = await showModalBottomSheet<_SleepTimerSelection>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF111419),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 2, 8, 12),
                child: Text(
                  'Temporizador para dormir',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
                ),
              ),
              for (final minutes in const [15, 30, 45, 60])
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: Text(minutes == 60 ? '1 hora' : '$minutes minutos'),
                  onTap: () => Navigator.pop(
                    context,
                    _SleepTimerSelection.minutes(minutes),
                  ),
                ),
              if (!widget.isLive)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(_hasEpisodes
                      ? 'Al terminar el episodio'
                      : 'Al terminar el contenido'),
                  onTap: () => Navigator.pop(
                    context,
                    const _SleepTimerSelection.atEnd(),
                  ),
                ),
              if (_sleepTimer != null || _sleepAtEpisodeEnd)
                ListTile(
                  leading: const Icon(Icons.timer_off_outlined),
                  title: const Text('Desactivar temporizador'),
                  onTap: () => Navigator.pop(
                    context,
                    const _SleepTimerSelection.cancel(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (selection == null) return;
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    _sleepAtEpisodeEnd = false;

    if (selection.cancelled) {
      if (mounted) setState(() {});
      _notice('Temporizador desactivado.');
      return;
    }
    if (selection.pauseAtEnd) {
      setState(() => _sleepAtEpisodeEnd = true);
      _notice(
        _hasEpisodes
            ? 'La reproducción se pausará al terminar el episodio.'
            : 'La reproducción se pausará al terminar el contenido.',
      );
      return;
    }

    final minutes = selection.minutes!;
    _sleepDeadline = DateTime.now().add(Duration(minutes: minutes));
    _sleepTimer = Timer(Duration(minutes: minutes), _pauseForSleepTimer);
    if (mounted) setState(() {});
    _notice(
      minutes == 60
          ? 'La reproducción se pausará en 1 hora.'
          : 'La reproducción se pausará en $minutes minutos.',
    );
  }

  Future<void> _pauseForSleepTimer() async {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepDeadline = null;
    _sleepAtEpisodeEnd = false;
    _cancelAutoNext();
    await _player.pause();
    if (!mounted) return;
    setState(() => _showControls = true);
    _notice('Temporizador finalizado. La reproducción se pausó.');
  }

  String get _sleepTimerLabel {
    if (_sleepAtEpisodeEnd) return _hasEpisodes ? 'Al final del episodio' : 'Al final';
    final deadline = _sleepDeadline;
    if (deadline == null) return 'Temporizador';
    final remaining = deadline.difference(DateTime.now());
    final minutes = remaining.inMinutes + (remaining.inSeconds.remainder(60) > 0 ? 1 : 0);
    return minutes <= 1 ? 'Dormir en 1 min' : 'Dormir en $minutes min';
  }

  Future<void> _setBrightness(double value) async {
    final normalized = value.clamp(0.05, 1).toDouble();
    setState(() => _brightness = normalized);
    try {
      await ScreenBrightness.instance
          .setApplicationScreenBrightness(normalized);
    } catch (_) {
      // Some Android versions reject app-level brightness changes.
    }
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_locked || _loading || _error != null) return;
    _controlsTimer?.cancel();
    final width = MediaQuery.sizeOf(context).width;
    _gestureControlsBrightness = details.localPosition.dx < width / 2;
    _showGestureOverlay(
      _gestureControlsBrightness ? _brightness : _volume / 200,
      _gestureControlsBrightness
          ? Icons.brightness_6_rounded
          : (_volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded),
      label: _gestureControlsBrightness ? null : '${_volume.round()}%',
    );
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_locked || _loading || _error != null) return;
    final height = MediaQuery.sizeOf(context).height.clamp(320.0, 1200.0);
    final delta = -details.delta.dy / (height * 0.62);
    if (_gestureControlsBrightness) {
      final next = (_brightness + delta).clamp(0.05, 1.0).toDouble();
      unawaited(_setBrightness(next));
      _showGestureOverlay(next, Icons.brightness_6_rounded);
    } else {
      final next = ((_volume / 200) + delta).clamp(0.0, 1.0).toDouble();
      _volume = next * 200;
      unawaited(_setAmplifiedVolume(_volume, persist: false));
      _showGestureOverlay(
        next,
        next <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
        label: '${_volume.round()}%',
      );
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _gestureOverlayTimer?.cancel();
    _gestureOverlayTimer = Timer(const Duration(milliseconds: 850), () {
      if (mounted) setState(() => _gestureOverlayValue = null);
    });
    if (!_gestureControlsBrightness) {
      unawaited(widget.appState.setPlaybackVolume(_volume));
    }
    _scheduleControlsHide();
  }

  void _showGestureOverlay(
    double value,
    IconData icon, {
    String? label,
  }) {
    _gestureOverlayTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _gestureOverlayValue = value.clamp(0.0, 1.0).toDouble();
      _gestureOverlayLabel = label;
      _gestureOverlayIcon = icon;
    });
  }

  Future<void> _changeAudioTrack(AudioTrack track) async {
    await _applyTrackChange(
      () => _setAudioTrackFast(track),
      pauseBeforeChange: false,
    );
  }

  Future<void> _changeSubtitleTrack(SubtitleTrack track) async {
    await _applyTrackChange(
      () => _setSubtitleTrackFast(track),
      pauseBeforeChange: false,
    );
  }

  Future<void> _setAudioTrackFast(AudioTrack track) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setAudioTrack(track, synchronized: false);
    } else {
      await _player.setAudioTrack(track);
    }
  }

  Future<void> _setSubtitleTrackFast(SubtitleTrack track) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setSubtitleTrack(track, synchronized: false);
    } else {
      await _player.setSubtitleTrack(track);
    }
  }

  Future<void> _applyTrackChange(
    Future<void> Function() change, {
    required bool pauseBeforeChange,
  }) async {
    if (_switchingTrack || _seeking) return;
    final anchor = _position;
    final wasPlaying = _player.state.playing;
    _ignoreProgressUntil = DateTime.now().add(const Duration(seconds: 5));
    if (mounted) setState(() => _switchingTrack = true);
    try {
      if (pauseBeforeChange && wasPlaying) await _player.pause();
      await change();
      await Future<void>.delayed(const Duration(milliseconds: 260));
      if (!widget.isLive) {
        final drift = (_displayPositionFor(_player.state.position) - anchor).abs();
        if (drift > const Duration(seconds: 3)) {
          await _performSeek(
            anchor,
            persistImmediately: false,
            showFailure: false,
          );
        }
      }
      if (pauseBeforeChange && wasPlaying) await _player.play();
    } catch (_) {
      _notice('No se pudo cambiar esta pista sin interrumpir el video.');
      if (pauseBeforeChange && wasPlaying) await _player.play();
    } finally {
      if (mounted) setState(() => _switchingTrack = false);
    }
  }

  Future<void> _applyStoredAudioPreferences() async {
    await _setAmplifiedVolume(_volume, persist: false, updateState: false);
  }

  Future<void> _setAmplifiedVolume(
    double value, {
    bool persist = true,
    bool updateState = true,
  }) async {
    final normalized = value.clamp(0.0, 200.0).toDouble();
    if (updateState && mounted) setState(() => _volume = normalized);
    try {
      final platform = _player.platform;
      if (platform is NativePlayer) {
        await platform.setProperty('volume-max', '200');
        await platform.setProperty(
          'volume',
          normalized.toStringAsFixed(1),
        );
      } else {
        await _player.setVolume(normalized.clamp(0.0, 100.0).toDouble());
      }
    } catch (_) {
      await _player.setVolume(normalized.clamp(0.0, 100.0).toDouble());
    }
    if (persist) await widget.appState.setPlaybackVolume(normalized);
  }

  Future<void> _showVolumeMenu() async {
    var selected = _volume;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171A1F),
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.volume_up_rounded),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Volumen del reproductor',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${selected.round()}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Slider(
                  value: selected,
                  min: 0,
                  max: 200,
                  divisions: 40,
                  label: '${selected.round()}%',
                  onChanged: (value) {
                    setSheetState(() => selected = value);
                    unawaited(
                      _setAmplifiedVolume(value, persist: false),
                    );
                  },
                  onChangeEnd: (value) {
                    unawaited(widget.appState.setPlaybackVolume(value));
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('0%'),
                    Text('100% normal'),
                    Text('200%'),
                  ],
                ),
                if (selected > 100) ...[
                  const SizedBox(height: 16),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.32),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(13),
                      child: Text(
                        'El volumen amplificado puede distorsionar algunos videos. Baja a 100% si escuchas saturación.',
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: () {
                    setSheetState(() => selected = 100);
                    unawaited(_setAmplifiedVolume(100));
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Restablecer a 100%'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _setSubtitleScale(double value) async {
    final normalized = value.clamp(0.75, 2.0).toDouble();
    if (mounted) setState(() => _subtitleScale = normalized);
    await widget.appState.setSubtitleScale(normalized);
  }

  Future<void> _showSubtitleSizeMenu() async {
    const options = <({String label, double value})>[
      (label: 'Pequeño', value: 0.75),
      (label: 'Normal', value: 1.0),
      (label: 'Grande', value: 1.25),
      (label: 'Muy grande', value: 1.5),
      (label: 'Extra grande', value: 1.75),
      (label: 'Máximo', value: 2.0),
    ];
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF171A1F),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            const ListTile(
              leading: Icon(Icons.format_size_rounded),
              title: Text(
                'Tamaño de subtítulos',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text('El cambio se aplica inmediatamente y queda guardado.'),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'Así se verán los subtítulos',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24 * _subtitleScale,
                  fontWeight: FontWeight.w700,
                  backgroundColor: const Color(0x99000000),
                ),
              ),
            ),
            ...options.map(
              (option) => RadioListTile<double>(
                value: option.value,
                groupValue: _subtitleScale,
                title: Text(option.label),
                subtitle: Text('${(option.value * 100).round()}%'),
                onChanged: (value) => Navigator.pop(context, value),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) await _setSubtitleScale(selected);
  }

  Future<void> _showSpeedMenu() async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final selected = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: const Color(0xFF171A1F),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              leading: Icon(Icons.speed_rounded),
              title: Text(
                'Velocidad de reproducción',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            ...speeds.map(
              (speed) => RadioListTile<double>(
                value: speed,
                groupValue: _rate,
                title: Text(speed == 1 ? 'Normal' : '${speed}x'),
                onChanged: (value) => Navigator.pop(context, value),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null) await _player.setRate(selected);
  }

  Future<void> _showLanguageMenu() async {
    final audioTracks = _tracks.audio;
    final subtitleTracks = <SubtitleTrack>[
      SubtitleTrack.no(),
      ..._tracks.subtitle.where((track) => track.id != 'no'),
    ];
    if (audioTracks.isEmpty && subtitleTracks.length <= 1) {
      _notice('Este video no informó pistas adicionales de audio o subtítulos.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF12151A),
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 28),
              children: [
                const ListTile(
                  leading: Icon(Icons.language_rounded),
                  title: Text(
                    'Audio y subtítulos',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Text('AUDIO', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                if (audioTracks.isEmpty)
                  const ListTile(title: Text('No hay pistas adicionales'))
                else
                  ...audioTracks.map(
                    (track) => RadioListTile<String>(
                      value: track.id,
                      groupValue: _selectedTrack.audio.id,
                      title: Text(_trackLabel(track, fallback: 'Pista de audio')),
                      subtitle: track.codec == null ? null : Text(track.codec!),
                      onChanged: (_) {
                        Navigator.pop(context);
                        unawaited(_changeAudioTrack(track));
                      },
                    ),
                  ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Text(
                    'SUBTÍTULOS',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                ...subtitleTracks.map(
                  (track) => RadioListTile<String>(
                    value: track.id,
                    groupValue: _selectedTrack.subtitle.id,
                    title: Text(
                      track.id == 'no'
                          ? 'Desactivados'
                          : _trackLabel(track, fallback: 'Subtítulos'),
                    ),
                    onChanged: (_) {
                      Navigator.pop(context);
                      unawaited(_changeSubtitleTrack(track));
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _cycleAspectRatio() {
    final next = (_aspectIndex + 1) % _aspectOptions.length;
    final option = _aspectOptions[next];
    setState(() {
      _aspectIndex = next;
      _fit = option.fit;
      _aspectRatio = option.ratio;
    });
    _notice('Relación de aspecto: ${option.label}');
  }

  Future<void> _showEpisodesMenu() async {
    if (!_hasEpisodes) return;
    final current = _currentEpisode!;
    final seasons = <int>{
      for (final entry in widget.episodes) entry.episode.seasonNumber,
    }.toList()
      ..sort();
    var selectedSeason = current.episode.seasonNumber;
    final selected = await showModalBottomSheet<PlayerEpisode>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111419),
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final episodes = widget.episodes
              .where((entry) => entry.episode.seasonNumber == selectedSeason)
              .toList(growable: false);
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.78,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Episodios',
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                          ),
                        ),
                        DropdownButton<int>(
                          value: selectedSeason,
                          dropdownColor: const Color(0xFF171B21),
                          items: seasons
                              .map(
                                (season) => DropdownMenuItem<int>(
                                  value: season,
                                  child: Text('Temporada $season'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setSheetState(() => selectedSeason = value);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      itemCount: episodes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = episodes[index];
                        final active = entry.episode.id == current.episode.id;
                        return ListTile(
                          selected: active,
                          selectedTileColor:
                              Theme.of(context).colorScheme.primary.withValues(alpha: 0.14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          leading: CircleAvatar(
                            child: Text('${entry.episode.episodeNumber}'),
                          ),
                          title: Text(
                            entry.episode.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '${entry.episode.numberLabel} • ${entry.episode.durationLabel}',
                          ),
                          trailing: active
                              ? const Icon(Icons.equalizer_rounded)
                              : const Icon(Icons.play_arrow_rounded),
                          onTap: () => Navigator.pop(context, entry),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (selected == null) return;
    final index = widget.episodes.indexWhere(
      (entry) => entry.episode.id == selected.episode.id,
    );
    await _switchEpisode(index);
  }

  String _trackLabel(dynamic track, {required String fallback}) {
    final title = '${track.title ?? ''}'.trim();
    final language = '${track.language ?? ''}'.trim();
    if (title.isNotEmpty && language.isNotEmpty) return '$title ($language)';
    if (title.isNotEmpty) return title;
    if (language.isNotEmpty) return language.toUpperCase();
    if ('${track.id}' == 'auto') return 'Automático';
    return '$fallback ${track.id}';
  }

  Future<void> _openCastSettings() async {
    final opened = await PlatformService.openCastSettings();
    if (!opened && mounted) {
      _notice('Este dispositivo no ofrece ajustes de transmisión de pantalla.');
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _beginScrub(double milliseconds) {
    final value = Duration(milliseconds: milliseconds.round());
    setState(() {
      _scrubbing = true;
      _scrubPosition = value;
    });
    _controlsTimer?.cancel();
    _schedulePreview(value);
  }

  Future<void> _endScrub(double milliseconds) async {
    final target = Duration(milliseconds: milliseconds.round());
    if (mounted) setState(() => _scrubbing = false);
    await _performSeek(target);
    _scheduleControlsHide();
  }

  void _schedulePreview(Duration target) {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_loadPreview(target));
    });
  }

  Future<void> _loadPreview(Duration target) async {
    final resource = _activeResource;
    if (resource.isEmpty || resource.toLowerCase().contains('.m3u8')) {
      if (mounted) setState(() => _previewBytes = null);
      return;
    }
    final key = (target.inMilliseconds / 10000).round() * 10000;
    if (_previewCache.containsKey(key)) {
      if (mounted) setState(() => _previewBytes = _previewCache[key]);
      return;
    }
    try {
      final bytes = await VideoThumbnail.thumbnailData(
        video: resource,
        headers: File(resource).existsSync() ? null : _httpHeaders,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 320,
        timeMs: key,
        quality: 55,
      );
      _previewCache[key] = bytes;
      if (_previewCache.length > 24) _previewCache.remove(_previewCache.keys.first);
      if (mounted && _scrubbing) setState(() => _previewBytes = bytes);
    } catch (_) {
      _previewCache[key] = null;
      if (mounted && _scrubbing) setState(() => _previewBytes = null);
    }
  }

  Future<void> _returnToCatalogWithPip() async {
    if (_locked) return;
    await _persistProgress();
    if (!mounted) return;

    if (!widget.openedInPlayerActivity || _loading || _error != null) {
      await _exitPlayer();
      return;
    }

    if (!widget.appState.pictureInPictureEnabled) {
      await _exitPlayer();
      return;
    }

    final supported = await PlatformService.isPictureInPictureSupported();
    if (!supported) {
      _notice('Picture-in-Picture requiere Android 8.0 o posterior.');
      await _exitPlayer();
      return;
    }

    final allowed = await PlatformService.isPictureInPictureAllowed();
    if (!allowed) {
      await _showPictureInPicturePermissionDialog();
      return;
    }

    await _syncPictureInPictureConfiguration();
    final entered = await PlatformService.enterPictureInPicture();
    if (!entered) {
      _notice('Android no pudo abrir la ventana flotante.');
      await _exitPlayer();
    }
  }

  Future<void> _exitPlayer() async {
    await _persistProgress();
    if (!mounted) return;
    if (widget.openedInPlayerActivity) {
      await PlatformService.configurePictureInPicture(
        enabled: false,
        autoEnter: false,
        isPlaying: false,
        hasNext: false,
        title: widget.title,
        subtitle: _activeSubtitle ?? '',
      );
      await PlatformService.closePictureInPictureActivity();
      return;
    }
    _allowRoutePop = true;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(_persistProgress());
    }
    if (state == AppLifecycleState.paused) {
      _pipAttemptedWhileLeaving = widget.appState.pictureInPictureEnabled &&
          widget.appState.pictureInPictureAutoEnter &&
          _playing;
      unawaited(_pauseIfPictureInPictureDidNotStart());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkPictureInPicturePermissionAfterReturn());
    }
  }

  Future<void> _pauseIfPictureInPictureDidNotStart() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!mounted || _lifecycleState != AppLifecycleState.paused) {
      return;
    }
    final isInPip = await PlatformService.isInPictureInPictureMode();
    if (!isInPip && _playing) await _player.pause();
  }

  Future<void> _checkPictureInPicturePermissionAfterReturn() async {
    if (!_pipAttemptedWhileLeaving || _inPictureInPicture) return;
    _pipAttemptedWhileLeaving = false;
    final supported = await PlatformService.isPictureInPictureSupported();
    if (!supported) return;
    final allowed = await PlatformService.isPictureInPictureAllowed();
    if (!allowed) await _showPictureInPicturePermissionDialog();
  }

  Future<void> prepareForReplacement() async {
    if (_preparingForReplacement || _playerDisposed) return;
    _preparingForReplacement = true;
    _controlsTimer?.cancel();
    _saveTimer?.cancel();
    _previewDebounce?.cancel();
    _autoNextTimer?.cancel();
    _sleepTimer?.cancel();
    _gestureOverlayTimer?.cancel();
    _stallTimer?.cancel();
    _liveHealthTimer?.cancel();
    _seekGeneration++;
    _pendingSeekTarget = null;
    _optimisticSeekTarget = null;

    try {
      await _persistProgress();
    } catch (_) {
      // El cambio de señal debe continuar aunque falle un guardado local.
    }

    for (final subscription in List<StreamSubscription<dynamic>>.from(
      _subscriptions,
    )) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    _subscriptions.clear();

    await _releasePlayer();
  }

  Future<void> _releasePlayer() async {
    if (_playerDisposed) return;
    _playerDisposed = true;
    try {
      await _player.setVolume(0);
    } catch (_) {}
    try {
      await _player.pause();
    } catch (_) {}
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appState.removeListener(_handleAppStateChanged);
    final ownedPictureInPictureChannel =
        PlatformService.clearPictureInPictureHandlers(owner: this);
    _controlsTimer?.cancel();
    _saveTimer?.cancel();
    _previewDebounce?.cancel();
    _autoNextTimer?.cancel();
    _sleepTimer?.cancel();
    _gestureOverlayTimer?.cancel();
    _stallTimer?.cancel();
    _liveHealthTimer?.cancel();
    unawaited(_persistProgress());
    if (ownedPictureInPictureChannel) {
      unawaited(
        PlatformService.configurePictureInPicture(
          enabled: false,
          autoEnter: false,
          isPlaying: false,
          hasNext: false,
          title: widget.title,
          subtitle: _activeSubtitle ?? '',
        ),
      );
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    unawaited(_releasePlayer());
    unawaited(ScreenBrightness.instance.resetApplicationScreenBrightness());
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_inPictureInPicture) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Video(
          controller: _videoController,
          controls: NoVideoControls,
          fit: BoxFit.contain,
          fill: Colors.black,
          wakelock: true,
          pauseUponEnteringBackgroundMode: false,
        ),
      );
    }
    return PopScope(
      canPop: _allowRoutePop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_locked) unawaited(_returnToCatalogWithPip());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleControls,
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: _videoController,
                controls: NoVideoControls,
                fit: _fit,
                aspectRatio: _aspectRatio,
                fill: Colors.black,
                wakelock: true,
                pauseUponEnteringBackgroundMode: false,
                subtitleViewConfiguration: SubtitleViewConfiguration(
                  style: TextStyle(
                    height: 1.3,
                    fontSize: (widget.appState.isTelevision ? 32 : 28) *
                        _subtitleScale,
                    color: Colors.white,
                    backgroundColor: const Color(0x99000000),
                    fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 82),
                ),
              ),
              if (_loading || _buffering)
                const IgnorePointer(
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (_error != null) _buildError(),
              if (_switchingTrack)
                const IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xAA000000),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
                ),
              if (_gestureOverlayValue != null) _buildGestureOverlay(),
              if (_locked)
                SafeArea(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: IconButton.filled(
                        tooltip: 'Desbloquear controles',
                        onPressed: () => setState(() {
                          _locked = false;
                          _showControls = true;
                        }),
                        icon: const Icon(Icons.lock_rounded),
                      ),
                    ),
                  ),
                )
              else if (_showControls && _error == null)
                _buildControls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGestureOverlay() {
    final value = _gestureOverlayValue ?? 0;
    return IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC101318),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          child: SizedBox(
            width: 170,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_gestureOverlayIcon, size: 34),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: value,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _gestureOverlayLabel ?? '${(value * 100).round()}%',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, size: 60),
                const SizedBox(height: 18),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 18, height: 1.45),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _initialize,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reintentar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exitPlayer,
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Regresar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  Future<void> _handleLiveRecording() async {
    if (!widget.isLive) return;
    await widget.appState.refreshRecordings();
    if (!mounted) return;
    final active = widget.appState.activeRecording;
    final channelId = widget.liveChannelId ?? widget.title;
    if (active != null) {
      if (active.sourceChannelId == channelId) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Detener grabación'),
            content: Text(
              '¿Deseas finalizar “${active.title}”? El video quedará guardado en Mis grabaciones.',
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
        final error = await widget.appState.stopLiveRecording();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error ?? 'Grabación guardada correctamente.')),
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Grabación en curso'),
            content: Text(
              'Se está grabando “${active.title}”. Puedes seguir viendo este canal, pero AVO TV permite una sola grabación simultánea.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final capability = widget.appState.recordingCapability;
    if (!capability.supported) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Grabación no disponible'),
          content: Text(capability.reason),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    final controller = TextEditingController(text: widget.title);
    var durationMinutes = 180;
    final selection = await showDialog<({String title, int minutes})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Grabar canal en vivo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la grabación',
                    hintText: 'Ejemplo: México vs. Argentina',
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: durationMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Duración máxima',
                  ),
                  items: const [
                    DropdownMenuItem(value: 60, child: Text('1 hora')),
                    DropdownMenuItem(value: 120, child: Text('2 horas')),
                    DropdownMenuItem(value: 180, child: Text('3 horas')),
                    DropdownMenuItem(value: 240, child: Text('4 horas')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => durationMinutes = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  'La grabación seguirá en segundo plano y podrás abrir otro canal, película o serie. Se utilizará una conexión adicional de tu cuenta.',
                  style: TextStyle(
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                final title = controller.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(
                  context,
                  (title: title, minutes: durationMinutes),
                );
              },
              icon: const Icon(Icons.fiber_manual_record_rounded),
              label: const Text('Comenzar'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (selection == null || !mounted) return;
    final error = await widget.appState.startLiveRecording(
      sourceChannelId: channelId,
      title: selection.title,
      channelTitle: widget.title,
      posterUrl: widget.previewImageUrl,
      urls: widget.urls,
      maxDurationMinutes: selection.minutes,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? 'Grabación iniciada. Puedes seguir usando AVO TV.',
        ),
      ),
    );
  }

  Widget _buildControls() {
    final canSeek = !widget.isLive && _duration > Duration.zero;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xD8000000), Color(0x22000000), Color(0xE8000000)],
          stops: [0, 0.48, 1],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Column(
            children: [
              _topBar(),
              const Spacer(),
              if (_autoNextSeconds > 0)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xDD15191F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.center,
                      children: [
                        Text(
                          'El siguiente episodio comenzará en $_autoNextSeconds segundos',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        FilledButton(
                          onPressed: () => _switchEpisode(_episodeIndex + 1),
                          child: const Text('Reproducir ahora'),
                        ),
                        TextButton(
                          onPressed: _cancelAutoNext,
                          child: const Text('Cancelar'),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_showUpNext && widget.onPlayUpNext != null)
                FilledButton.icon(
                  onPressed: () => widget.onPlayUpNext!(),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Siguiente: ${widget.upNextTitle ?? 'Recomendación'}'),
                ),
              const SizedBox(height: 10),
              _centerControls(canSeek),
              const Spacer(),
              _playerTitleBlock(),
              const SizedBox(height: 8),
              if (canSeek) _progressControl(),
              _bottomActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Row(
      children: [
        IconButton(
          tooltip: 'Volver al catálogo',
          onPressed: _returnToCatalogWithPip,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Ventana flotante',
          onPressed: _enterPictureInPictureManually,
          icon: const Icon(Icons.picture_in_picture_alt_rounded),
        ),
        IconButton(
          tooltip: 'Transmitir pantalla',
          onPressed: _openCastSettings,
          icon: const Icon(Icons.cast_rounded),
        ),
        IconButton(
          tooltip: 'Bloquear pantalla',
          onPressed: () => setState(() {
            _locked = true;
            _showControls = false;
          }),
          icon: const Icon(Icons.lock_open_rounded),
        ),
      ],
    );
  }

  Widget _playerTitleBlock() {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            if (_activeSubtitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                _activeSubtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _centerControls(bool canSeek) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_hasEpisodes)
          IconButton(
            tooltip: 'Episodio anterior',
            onPressed: _episodeIndex > 0
                ? () => _switchEpisode(_episodeIndex - 1)
                : null,
            iconSize: 34,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
        if (canSeek)
          IconButton.filledTonal(
            tooltip: 'Retroceder 10 segundos',
            onPressed: () => _seekRelative(-10),
            icon: const Icon(Icons.replay_10_rounded),
          ),
        const SizedBox(width: 16),
        IconButton.filled(
          tooltip: _playing ? 'Pausar' : 'Reproducir',
          onPressed: _togglePlayback,
          iconSize: 42,
          padding: const EdgeInsets.all(15),
          icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 16),
        if (canSeek)
          IconButton.filledTonal(
            tooltip: 'Adelantar 10 segundos',
            onPressed: () => _seekRelative(10),
            icon: const Icon(Icons.forward_10_rounded),
          ),
        if (_hasEpisodes)
          IconButton(
            tooltip: 'Episodio siguiente',
            onPressed: _episodeIndex + 1 < widget.episodes.length
                ? () => _switchEpisode(_episodeIndex + 1)
                : null,
            iconSize: 34,
            icon: const Icon(Icons.skip_next_rounded),
          ),
      ],
    );
  }

  Widget _progressControl() {
    final shown = _scrubbing ? _scrubPosition : _position;
    return LayoutBuilder(
      builder: (context, constraints) {
        final previewWidth =
            (constraints.maxWidth.clamp(130.0, 220.0) * 0.75).toDouble();
        final ratio = _duration.inMilliseconds <= 0
            ? 0.0
            : (shown.inMilliseconds / _duration.inMilliseconds)
                .clamp(0.0, 1.0);
        final left = (constraints.maxWidth - previewWidth) * ratio;
        return Column(
          children: [
            if (_scrubbing)
              SizedBox(
                height: 106,
                child: Stack(
                  children: [
                    Positioned(
                      left: left,
                      bottom: 4,
                      width: previewWidth,
                      child: _previewCard(shown),
                    ),
                  ],
                ),
              ),
            Slider(
              value: shown.inMilliseconds
                  .clamp(0, _duration.inMilliseconds)
                  .toDouble(),
              max: _duration.inMilliseconds.toDouble(),
              onChanged: _beginScrub,
              onChangeEnd: (value) => unawaited(_endScrub(value)),
            ),
          ],
        );
      },
    );
  }

  Widget _previewCard(Duration target) {
    Widget image;
    if (_previewBytes != null) {
      image = Image.memory(_previewBytes!, fit: BoxFit.cover, gaplessPlayback: true);
    } else if (_activePreviewImageUrl.trim().isNotEmpty) {
      image = Image.network(
        _activePreviewImageUrl,
        headers: _httpHeaders,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const ColoredBox(color: Color(0xFF20242A)),
      );
    } else {
      image = const ColoredBox(
        color: Color(0xFF20242A),
        child: Center(child: Icon(Icons.movie_outlined)),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF111419),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(aspectRatio: 16 / 9, child: image),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                _formatDuration(target),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomActions() {
    return Row(
      children: [
        Flexible(
          child: widget.isLive
              ? const Align(
                  alignment: Alignment.centerLeft,
                  child: _LiveBadge(),
                )
              : Text(
                  '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasEpisodes)
                  _controlAction(
                    icon: Icons.skip_previous_rounded,
                    label: 'Anterior',
                    onTap: _episodeIndex > 0
                        ? () => _switchEpisode(_episodeIndex - 1)
                        : null,
                  ),
                if (_hasEpisodes)
                  _controlAction(
                    icon: Icons.video_library_rounded,
                    label: 'Episodios',
                    onTap: _showEpisodesMenu,
                  ),
                if (_hasEpisodes)
                  _controlAction(
                    icon: Icons.skip_next_rounded,
                    label: 'Siguiente',
                    onTap: _episodeIndex + 1 < widget.episodes.length
                        ? () => _switchEpisode(_episodeIndex + 1)
                        : null,
                  ),
                if (widget.isLive)
                  _controlAction(
                    icon: widget.appState.activeRecording?.sourceChannelId ==
                            widget.liveChannelId
                        ? Icons.stop_rounded
                        : Icons.fiber_manual_record_rounded,
                    label: widget.appState.activeRecording == null
                        ? 'Grabar'
                        : widget.appState.activeRecording?.sourceChannelId ==
                                widget.liveChannelId
                            ? 'Detener grabación'
                            : 'Grabando otro canal',
                    onTap: _handleLiveRecording,
                  ),
                _controlAction(
                  icon: _volume > 100
                      ? Icons.volume_up_rounded
                      : Icons.volume_down_rounded,
                  label: 'Volumen ${_volume.round()}%',
                  onTap: _showVolumeMenu,
                ),
                _controlAction(
                  icon: Icons.format_size_rounded,
                  label: 'Subtítulos ${(100 * _subtitleScale).round()}%',
                  onTap: _showSubtitleSizeMenu,
                ),
                _controlAction(
                  icon: Icons.subtitles_rounded,
                  label: 'Audio y subtítulos',
                  onTap: _showLanguageMenu,
                ),
                if (!widget.isLive)
                  _controlAction(
                    icon: Icons.first_page_rounded,
                    label: 'Desde el inicio',
                    onTap: () => _performSeek(Duration.zero),
                  ),
                if (!widget.isLive)
                  _controlAction(
                    icon: Icons.speed_rounded,
                    label: _rate == 1 ? 'Velocidad' : '${_rate}x',
                    onTap: _showSpeedMenu,
                  ),
                _controlAction(
                  icon: Icons.bedtime_outlined,
                  label: _sleepTimerLabel,
                  onTap: _showSleepTimerMenu,
                ),
                _controlAction(
                  icon: Icons.aspect_ratio_rounded,
                  label: _aspectLabel,
                  onTap: _cycleAspectRatio,
                ),
                if (_activeUrls.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Tooltip(
                      message:
                          'Fuente ${_activeUrlIndex + 1} de ${_activeUrls.length}',
                      child: const Icon(Icons.network_check_rounded),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _controlAction({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 21),
        label: Text(label),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _SleepTimerSelection {
  const _SleepTimerSelection.minutes(this.minutes)
      : pauseAtEnd = false,
        cancelled = false;

  const _SleepTimerSelection.atEnd()
      : minutes = null,
        pauseAtEnd = true,
        cancelled = false;

  const _SleepTimerSelection.cancel()
      : minutes = null,
        pauseAtEnd = false,
        cancelled = true;

  final int? minutes;
  final bool pauseAtEnd;
  final bool cancelled;
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.redAccent,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'EN VIVO',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
