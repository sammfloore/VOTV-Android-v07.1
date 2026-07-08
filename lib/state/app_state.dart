import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/demo_catalog.dart';
import '../models/app_session.dart';
import '../models/media_item.dart';
import '../models/live_recording.dart';
import '../models/offline_download.dart';
import '../models/series_details.dart';
import '../services/catalog_cache_service.dart';
import '../services/catalog_search_service.dart';
import '../services/download_service.dart';
import '../services/iptv_api_service.dart';
import '../services/local_store.dart';
import '../services/platform_service.dart';
import '../services/session_store.dart';

class AppState extends ChangeNotifier {
  AppState({
    LocalStore? store,
    SessionStore? sessionStore,
    IptvApiService? api,
    DownloadService? downloadService,
    CatalogCacheService? catalogCacheService,
  })  : _store = store ?? LocalStore(),
        _sessionStore = sessionStore ?? SessionStore(),
        _api = api ?? IptvApiService(),
        _downloadService = downloadService ?? DownloadService(),
        _catalogCacheService = catalogCacheService ?? CatalogCacheService();

  final LocalStore _store;
  final SessionStore _sessionStore;
  final IptvApiService _api;
  final DownloadService _downloadService;
  final CatalogCacheService _catalogCacheService;

  List<MediaItem> _catalog = const [];
  List<MediaItem> _movies = const [];
  List<MediaItem> _series = const [];
  List<MediaItem> _liveChannels = const [];
  List<MediaItem> _recentlyAdded = const [];
  List<String> _liveCategoryNames = const [];
  List<MediaItem>? _recommendationsCache;
  final CatalogSearchService _catalogSearch = CatalogSearchService();
  Map<String, MediaItem> _itemsById = const {};
  Set<String> _favorites = {};
  Map<String, double> _progress = {};
  Map<String, double> _episodeProgress = {};
  Map<String, String> _lastEpisodeBySeries = {};
  List<String> _history = [];
  List<OfflineDownload> _downloads = [];
  List<LiveRecording> _recordings = [];
  RecordingCapability _recordingCapability =
      const RecordingCapability.unavailable('Verificando almacenamiento…');
  Timer? _recordingRefreshTimer;
  final Map<String, double> _downloadProgress = {};
  final Set<String> _activeDownloads = {};
  AppSession? _session;
  bool _ready = false;
  bool _isRefreshingCatalog = false;
  bool _offlineMode = false;
  String _bootMessage = 'Preparando AVO TV…';
  String? _startupError;
  String? _catalogMessage;
  DateTime? _lastCatalogRefresh;
  bool _pictureInPictureEnabled = true;
  bool _pictureInPictureAutoEnter = true;
  bool _isTelevision = false;
  double _playbackVolume = 100.0;
  double _subtitleScale = 1.0;

  bool get ready => _ready;
  bool get signedIn => _session != null;
  bool get isDemo => _session?.isDemo ?? false;
  bool get offlineMode => _offlineMode;
  bool get isRefreshingCatalog => _isRefreshingCatalog;
  String get accountName => _session?.accountName ?? '';
  String get bootMessage => _bootMessage;
  String? get startupError => _startupError;
  String? get catalogMessage => _catalogMessage;
  DateTime? get lastCatalogRefresh => _lastCatalogRefresh;
  bool get pictureInPictureEnabled => _pictureInPictureEnabled;
  bool get pictureInPictureAutoEnter => _pictureInPictureAutoEnter;
  bool get isTelevision => _isTelevision;
  double get playbackVolume => _playbackVolume;
  double get subtitleScale => _subtitleScale;
  LoginCredentials? get credentials => _session?.credentials;
  List<MediaItem> get catalog => UnmodifiableListView(_catalog);
  Set<String> get favorites => Set.unmodifiable(_favorites);
  Map<String, double> get progress => Map.unmodifiable(_progress);
  List<String> get history => List.unmodifiable(_history);
  List<OfflineDownload> get downloads => UnmodifiableListView(_downloads);
  List<LiveRecording> get recordings => UnmodifiableListView(_recordings);
  RecordingCapability get recordingCapability => _recordingCapability;
  LiveRecording? get activeRecording {
    for (final item in _recordings) {
      if (item.isActive) return item;
    }
    return null;
  }

  Future<void> initializePlaybackOnly() async {
    await _loadPlaybackState();
    _ready = true;
    notifyListeners();
  }

  Future<void> reloadPlaybackActivity() async {
    if (!_ready) return;
    await _store.reload();
    await _loadPlaybackState();
    notifyListeners();
  }

  Future<void> _loadPlaybackState() async {
    final values = await Future.wait<dynamic>([
      _store.loadProgress(),
      _store.loadHistory(),
      _store.loadEpisodeProgress(),
      _store.loadLastEpisodes(),
      _store.loadPictureInPictureEnabled(),
      _store.loadPictureInPictureAutoEnter(),
      _store.loadPlaybackVolume(),
      _store.loadSubtitleScale(),
      PlatformService.isTelevision(),
    ]);
    _progress = values[0] as Map<String, double>;
    _history = values[1] as List<String>;
    _episodeProgress = values[2] as Map<String, double>;
    _lastEpisodeBySeries = values[3] as Map<String, String>;
    _pictureInPictureEnabled = values[4] as bool;
    _pictureInPictureAutoEnter = values[5] as bool;
    _playbackVolume = values[6] as double;
    _subtitleScale = values[7] as double;
    _isTelevision = values[8] as bool;
    _recommendationsCache = null;
  }

  Future<void> initialize() async {
    await _downloadService.initialize();
    _bootMessage = 'Cargando tus preferencias…';
    notifyListeners();

    final values = await Future.wait<dynamic>([
      _store.loadFavorites(),
      _store.loadProgress(),
      _store.loadHistory(),
      _store.loadEpisodeProgress(),
      _store.loadLastEpisodes(),
      _sessionStore.load(),
      _downloadService.load(),
      _store.loadCatalogRefresh(),
      _store.loadPictureInPictureEnabled(),
      _store.loadPictureInPictureAutoEnter(),
      _store.loadPlaybackVolume(),
      _store.loadSubtitleScale(),
      PlatformService.isTelevision(),
    ]);

    _favorites = values[0] as Set<String>;
    _progress = values[1] as Map<String, double>;
    _history = values[2] as List<String>;
    _episodeProgress = values[3] as Map<String, double>;
    _lastEpisodeBySeries = values[4] as Map<String, String>;
    final savedCredentials = values[5] as LoginCredentials?;
    _downloads = values[6] as List<OfflineDownload>;
    _lastCatalogRefresh = values[7] as DateTime?;
    _pictureInPictureEnabled = values[8] as bool;
    _pictureInPictureAutoEnter = values[9] as bool;
    _playbackVolume = values[10] as double;
    _subtitleScale = values[11] as double;
    _isTelevision = values[12] as bool;
    await refreshRecordings(notify: false);

    if (savedCredentials != null) {
      _bootMessage = 'Abriendo tu catálogo…';
      notifyListeners();

      final cached = await _catalogCacheService.load(savedCredentials);
      if (cached.isNotEmpty) {
        _setCatalog(cached);
        _session = AppSession(
          accountName: _profileName(savedCredentials),
          isDemo: false,
          credentials: savedCredentials,
        );
      }

      if (cached.isNotEmpty &&
          _catalogWasUpdatedToday() &&
          savedCredentials.hasResolvedProvider) {
        _offlineMode = false;
        unawaited(_refreshServerBindingInBackground(savedCredentials));
      } else {
        _bootMessage = cached.isEmpty
            ? 'Cargando películas, series y canales…'
            : 'Buscando novedades del catálogo…';
        notifyListeners();

        final auth = await _api.authenticate(savedCredentials);
        if (auth.success) {
          final activeCredentials = auth.resolvedCredentials ?? savedCredentials;
          final loaded = await _api.loadCatalog(activeCredentials);
          if (loaded.isNotEmpty) {
            _setCatalog(loaded);
            _session = AppSession(
              accountName: _profileName(activeCredentials),
              isDemo: false,
              credentials: activeCredentials,
            );
            _offlineMode = false;
            _lastCatalogRefresh = DateTime.now();
            await Future.wait([
              _sessionStore.save(activeCredentials),
              _store.saveCatalogRefresh(_lastCatalogRefresh!),
            ]);
            unawaited(_catalogCacheService.save(activeCredentials, loaded));
          } else if (cached.isNotEmpty) {
            _offlineMode = true;
            _catalogMessage =
                'No se recibieron novedades. Se conservó el catálogo guardado.';
          } else {
            _startupError =
                'El servicio aceptó la cuenta, pero no entregó contenido.';
          }
        } else if (cached.isNotEmpty || _downloads.isNotEmpty) {
          _session ??= AppSession(
            accountName: _profileName(savedCredentials),
            isDemo: false,
            credentials: savedCredentials,
          );
          _offlineMode = true;
          _catalogMessage = cached.isNotEmpty
              ? 'Sin conexión. Se muestra el último catálogo guardado y tus descargas.'
              : 'Sin conexión. Puedes reproducir el contenido guardado en Descargas.';
        } else {
          _startupError = 'No se pudo abrir la cuenta. ${auth.message}';
          await _sessionStore.clear();
        }
      }
    }

    _ready = true;
    notifyListeners();
  }

  Future<AuthResult> signIn(LoginCredentials credentials) async {
    final auth = await _api.authenticate(credentials);
    if (!auth.success) return auth;

    final activeCredentials = auth.resolvedCredentials ?? credentials;
    final loaded = await _api.loadCatalog(activeCredentials);
    if (loaded.isEmpty) {
      return const AuthResult(
        success: false,
        message: 'La cuenta fue aceptada, pero el servicio no entregó contenido.',
      );
    }
    _setCatalog(loaded);
    _session = AppSession(
      accountName: _profileName(activeCredentials),
      isDemo: false,
      credentials: activeCredentials,
    );
    _offlineMode = false;
    _startupError = null;
    _catalogMessage = null;
    _lastCatalogRefresh = DateTime.now();

    await Future.wait([
      _store.saveRememberedLogin(
        profileName: activeCredentials.profileName,
        username: activeCredentials.username,
      ),
      _sessionStore.save(activeCredentials),
      _store.saveCatalogRefresh(_lastCatalogRefresh!),
    ]);
    unawaited(_catalogCacheService.save(activeCredentials, loaded));

    notifyListeners();
    return AuthResult(
      success: true,
      message: auth.message,
      accountName: _session!.accountName,
      resolvedCredentials: activeCredentials,
    );
  }

  Future<void> _refreshServerBindingInBackground(
    LoginCredentials previousCredentials,
  ) async {
    try {
      final auth = await _api.authenticate(previousCredentials);
      if (!auth.success) return;
      final activeCredentials =
          auth.resolvedCredentials ?? previousCredentials;
      final providerChanged = activeCredentials.providerCacheKey !=
          previousCredentials.providerCacheKey;

      if (!providerChanged) {
        await _sessionStore.save(activeCredentials);
        return;
      }

      final loaded = await _api.loadCatalog(activeCredentials);
      if (loaded.isEmpty) return;
      _setCatalog(loaded);
      _session = AppSession(
        accountName: _profileName(activeCredentials),
        isDemo: false,
        credentials: activeCredentials,
      );
      _offlineMode = false;
      _lastCatalogRefresh = DateTime.now();
      _catalogMessage = 'El servicio se actualizó automáticamente.';
      await Future.wait([
        _sessionStore.save(activeCredentials),
        _store.saveCatalogRefresh(_lastCatalogRefresh!),
      ]);
      unawaited(_catalogCacheService.save(activeCredentials, loaded));
      notifyListeners();
    } catch (_) {
      // El catálogo guardado continúa disponible aunque falle la comprobación.
    }
  }

  Future<void> refreshDownloads() async {
    try {
      final latest = await _downloadService.refreshFromBackground();
      _downloads = latest;
      notifyListeners();
    } catch (_) {
      // A catalog refresh must not fail because Android delayed a download event.
    }
  }


  Future<void> refreshRecordings({bool notify = true}) async {
    try {
      final values = await Future.wait<dynamic>([
        PlatformService.listLiveRecordings(),
        PlatformService.recordingCapability(),
      ]);
      final rawRecordings = values[0] as List<Map<String, dynamic>>;
      _recordings = rawRecordings
          .map(LiveRecording.fromMap)
          .where((item) => item.id.isNotEmpty)
          .toList(growable: true)
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      final rawCapability = values[1] as Map<String, dynamic>;
      _recordingCapability = rawCapability.isEmpty
          ? const RecordingCapability.unavailable(
              'La grabación local no está disponible en este dispositivo.',
            )
          : RecordingCapability.fromMap(rawCapability);
      _syncRecordingRefreshTimer();
      if (notify) notifyListeners();
    } catch (_) {
      _recordingCapability = const RecordingCapability.unavailable(
        'No se pudo comprobar el almacenamiento del dispositivo.',
      );
      _recordingRefreshTimer?.cancel();
      _recordingRefreshTimer = null;
      if (notify) notifyListeners();
    }
  }

  void _syncRecordingRefreshTimer() {
    if (activeRecording == null) {
      _recordingRefreshTimer?.cancel();
      _recordingRefreshTimer = null;
      return;
    }
    _recordingRefreshTimer ??= Timer.periodic(
      const Duration(seconds: 3),
      (_) => unawaited(refreshRecordings()),
    );
  }

  LiveRecording? recordingForChannel(String channelId) {
    for (final item in _recordings) {
      if (item.isActive && item.sourceChannelId == channelId) return item;
    }
    return null;
  }

  Future<String?> startLiveRecording({
    required String sourceChannelId,
    required String title,
    required String channelTitle,
    required String posterUrl,
    required List<String> urls,
    required int maxDurationMinutes,
  }) async {
    await refreshRecordings(notify: false);
    final capability = _recordingCapability;
    if (!capability.supported) {
      notifyListeners();
      return capability.reason.isEmpty
          ? 'Este dispositivo no cumple los requisitos de almacenamiento.'
          : capability.reason;
    }
    if (activeRecording != null) {
      notifyListeners();
      return 'Ya existe una grabación en curso. Deténla antes de iniciar otra.';
    }
    final permission =
        await PlatformService.requestRecordingNotificationPermission();
    if (!permission) {
      await refreshRecordings(notify: false);
      notifyListeners();
      return 'AVO TV necesita permiso de notificaciones para mostrar y controlar la grabación en segundo plano.';
    }
    final response = await PlatformService.startLiveRecording(
      sourceChannelId: sourceChannelId,
      title: title,
      channelTitle: channelTitle,
      posterUrl: posterUrl,
      urls: urls,
      maxDurationMinutes: maxDurationMinutes,
    );
    await refreshRecordings(notify: false);
    notifyListeners();
    if (response['success'] == true) return null;
    return '${response['message'] ?? 'No se pudo iniciar la grabación.'}';
  }

  Future<String?> stopLiveRecording() async {
    final response = await PlatformService.stopLiveRecording();
    if (response['success'] == true) {
      for (var attempt = 0; attempt < 20; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await refreshRecordings(notify: false);
        if (activeRecording == null) break;
      }
    } else {
      await refreshRecordings(notify: false);
    }
    notifyListeners();
    if (response['success'] == true) return null;
    return '${response['message'] ?? 'No se pudo detener la grabación.'}';
  }

  Future<bool> deleteLiveRecording(LiveRecording recording) async {
    if (recording.isActive) return false;
    final removed = await PlatformService.deleteLiveRecording(recording.id);
    if (removed) {
      _recordings.removeWhere((item) => item.id == recording.id);
      notifyListeners();
    }
    return removed;
  }

  Future<bool> refreshCatalogIfStale() async {
    if (_catalogWasUpdatedToday() || isDemo) return false;
    return refreshCatalog();
  }

  Future<bool> refreshCatalog() async {
    if (isDemo || _isRefreshingCatalog) return false;
    final login = credentials;
    if (login == null) return false;

    _isRefreshingCatalog = true;
    _catalogMessage = null;
    notifyListeners();
    try {
      final auth = await _api.authenticate(login);
      if (!auth.success) {
        _catalogMessage = auth.message;
        return false;
      }
      final activeCredentials = auth.resolvedCredentials ?? login;
      final loaded = await _api.loadCatalog(activeCredentials);
      if (loaded.isEmpty) {
        _catalogMessage = 'El servicio no entregó contenido para esta cuenta.';
        return false;
      }
      _setCatalog(loaded);
      _session = AppSession(
        accountName: _profileName(activeCredentials),
        isDemo: false,
        credentials: activeCredentials,
      );
      _offlineMode = false;
      _lastCatalogRefresh = DateTime.now();
      _catalogMessage =
          'Catálogo actualizado: ${movies.length} películas, ${series.length} series y ${liveChannels.length} canales.';
      await Future.wait([
        _sessionStore.save(activeCredentials),
        _store.saveCatalogRefresh(_lastCatalogRefresh!),
      ]);
      unawaited(_catalogCacheService.save(activeCredentials, loaded));
      return true;
    } catch (_) {
      _catalogMessage = 'No se pudo actualizar el catálogo. Intenta de nuevo.';
      return false;
    } finally {
      _isRefreshingCatalog = false;
      notifyListeners();
    }
  }

  void enterDemo() {
    _setCatalog(_buildDemoCatalog());
    _session = const AppSession(accountName: 'Invitado', isDemo: true);
    _offlineMode = false;
    _startupError = null;
    notifyListeners();
  }

  Future<void> signOut() async {
    await Future.wait([
      _sessionStore.clear(),
      _catalogCacheService.clear(),
      _store.clearCatalogRefresh(),
    ]);
    _session = null;
    _setCatalog(const []);
    _offlineMode = false;
    _lastCatalogRefresh = null;
    notifyListeners();
  }

  Future<void> setPictureInPictureEnabled(bool value) async {
    if (_pictureInPictureEnabled == value) return;
    _pictureInPictureEnabled = value;
    notifyListeners();
    await _store.savePictureInPictureEnabled(value);
  }

  Future<void> setPictureInPictureAutoEnter(bool value) async {
    if (_pictureInPictureAutoEnter == value) return;
    _pictureInPictureAutoEnter = value;
    notifyListeners();
    await _store.savePictureInPictureAutoEnter(value);
  }


  Future<void> setPlaybackVolume(double value) async {
    final normalized = value.clamp(0.0, 200.0).toDouble();
    if ((_playbackVolume - normalized).abs() < 0.1) return;
    _playbackVolume = normalized;
    notifyListeners();
    await _store.savePlaybackVolume(normalized);
  }

  Future<void> setSubtitleScale(double value) async {
    final normalized = value.clamp(0.75, 2.0).toDouble();
    if ((_subtitleScale - normalized).abs() < 0.001) return;
    _subtitleScale = normalized;
    notifyListeners();
    await _store.saveSubtitleScale(normalized);
  }

  Future<String> loadTrailer(MediaItem item) async {
    if (item.trailerUrl.trim().isNotEmpty) return item.trailerUrl.trim();
    if (item.type != MediaType.movie || isDemo || _offlineMode) return '';
    final login = credentials;
    if (login == null || item.providerId.isEmpty) return '';
    return _api.loadVodTrailer(login, item.providerId);
  }

  Future<SeriesDetails> loadSeriesDetails(MediaItem series) async {
    if (series.type != MediaType.series) {
      throw ArgumentError('El contenido seleccionado no es una serie.');
    }
    if (isDemo) return _demoSeriesDetails(series);
    if (_offlineMode) {
      throw StateError('Conéctate a internet para cargar episodios nuevos.');
    }
    final login = credentials;
    if (login == null || series.providerId.isEmpty) {
      throw StateError('No hay una sesión válida para cargar los episodios.');
    }
    return _api.loadSeriesDetails(login, series.providerId);
  }

  MediaItem? findById(String id) => _itemsById[id];

  bool isFavorite(MediaItem item) => _favorites.contains(item.id);
  double progressFor(MediaItem item) => _progress[item.id] ?? 0;
  double episodeProgress(String episodeId) => _episodeProgress[episodeId] ?? 0;
  String? lastEpisodeId(MediaItem series) => _lastEpisodeBySeries[series.id];

  EpisodeItem resumeEpisodeFor(MediaItem series, SeriesDetails details) {
    final episodes = details.allEpisodes;
    if (episodes.isEmpty) {
      throw StateError('Esta serie no tiene episodios disponibles.');
    }
    final lastId = _lastEpisodeBySeries[series.id];
    if (lastId == null) return episodes.first;
    final index = episodes.indexWhere((episode) => episode.id == lastId);
    if (index < 0) return episodes.first;
    final current = episodes[index];
    final progress = _episodeProgress[current.id] ?? 0;
    if (progress >= 0.95 && index + 1 < episodes.length) {
      return episodes[index + 1];
    }
    return current;
  }

  Future<void> markEpisodeStarted(
    MediaItem series,
    EpisodeItem episode,
  ) async {
    _lastEpisodeBySeries[series.id] = episode.id;
    _progress[series.id] = math.max(0.04, _progress[series.id] ?? 0).toDouble();
    _history.remove(series.id);
    _history.insert(0, series.id);
    _recommendationsCache = null;
    notifyListeners();
    await Future.wait([
      _store.saveProgress(_progress),
      _store.saveEpisodeProgress(_episodeProgress),
      _store.saveLastEpisodes(_lastEpisodeBySeries),
      _store.saveHistory(_history),
    ]);
  }

  Future<void> saveSeriesEpisodeProgress(
    MediaItem series,
    SeriesDetails details,
    EpisodeItem episode,
    double value,
  ) async {
    final normalized = value.clamp(0.0, 1.0).toDouble();
    _episodeProgress[episode.id] = normalized;
    final episodes = details.allEpisodes;
    final index = episodes.indexWhere((candidate) => candidate.id == episode.id);
    if (normalized >= 0.95 && index >= 0 && index + 1 < episodes.length) {
      final next = episodes[index + 1];
      _lastEpisodeBySeries[series.id] = next.id;
      _progress[series.id] = 0.04;
    } else {
      _lastEpisodeBySeries[series.id] = episode.id;
      _progress[series.id] = normalized >= 0.95
          ? 1.0
          : math.max(0.04, normalized).toDouble();
    }
    _history.remove(series.id);
    _history.insert(0, series.id);
    _recommendationsCache = null;
    notifyListeners();
    await Future.wait([
      _store.saveProgress(_progress),
      _store.saveEpisodeProgress(_episodeProgress),
      _store.saveLastEpisodes(_lastEpisodeBySeries),
      _store.saveHistory(_history),
    ]);
  }

  MediaItem? upNextFor(MediaItem item) {
    final candidates = _catalog.where((candidate) {
      return candidate.id != item.id &&
          !candidate.isLive &&
          candidate.type == item.type;
    });
    final root = _titleRoot(item.title);
    MediaItem? best;
    var bestScore = double.negativeInfinity;
    for (final candidate in candidates) {
      var score = candidate.rating;
      final candidateRoot = _titleRoot(candidate.title);
      if (item.franchise != null &&
          item.franchise!.trim().isNotEmpty &&
          candidate.franchise?.toLowerCase() == item.franchise!.toLowerCase()) {
        score += 80;
      }
      if (root.length >= 4 && candidateRoot == root) score += 55;
      if (root.length >= 4 && candidateRoot.startsWith(root)) score += 28;
      score += candidate.genres.where(item.genres.contains).length * 7;
      score += candidate.cast.where(item.cast.contains).length * 3;
      if (candidate.year >= item.year) score += 2;
      if ((_progress[candidate.id] ?? 0) >= 0.95) score -= 30;
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  Future<void> toggleFavorite(MediaItem item) async {
    if (!_favorites.add(item.id)) _favorites.remove(item.id);
    notifyListeners();
    await _store.saveFavorites(_favorites);
  }

  Future<void> markLiveChannelOpened(MediaItem item) async {
    if (!item.isLive) return;
    _history.remove(item.id);
    _history.insert(0, item.id);
    if (_history.length > 240) {
      _history = _history.take(240).toList(growable: true);
    }
    notifyListeners();
    await _store.saveHistory(_history);
  }

  Future<void> savePlaybackProgress(
    MediaItem item,
    double value, {
    String? episodeId,
  }) async {
    if (item.isLive) return;
    final normalized = value.clamp(0.0, 1.0).toDouble();

    if (episodeId != null) {
      _episodeProgress[episodeId] = normalized;
      _lastEpisodeBySeries[item.id] = episodeId;
      _progress[item.id] = normalized >= 0.95
          ? 0.78
          : math.max(0.04, normalized).toDouble();
    } else {
      _progress[item.id] = normalized;
    }

    _history.remove(item.id);
    _history.insert(0, item.id);
    _recommendationsCache = null;
    notifyListeners();

    await Future.wait([
      _store.saveProgress(_progress),
      _store.saveHistory(_history),
      if (episodeId != null) _store.saveEpisodeProgress(_episodeProgress),
      if (episodeId != null) _store.saveLastEpisodes(_lastEpisodeBySeries),
    ]);
  }

  Future<void> restart(MediaItem item) async {
    _progress[item.id] = 0;
    final episodeId = _lastEpisodeBySeries.remove(item.id);
    if (episodeId != null) _episodeProgress[episodeId] = 0;
    _recommendationsCache = null;
    notifyListeners();
    await Future.wait([
      _store.saveProgress(_progress),
      _store.saveEpisodeProgress(_episodeProgress),
      _store.saveLastEpisodes(_lastEpisodeBySeries),
    ]);
  }

  Future<void> restartEpisode(MediaItem series, EpisodeItem episode) async {
    _episodeProgress[episode.id] = 0;
    _lastEpisodeBySeries[series.id] = episode.id;
    _progress[series.id] = 0;
    _recommendationsCache = null;
    notifyListeners();
    await Future.wait([
      _store.saveProgress(_progress),
      _store.saveEpisodeProgress(_episodeProgress),
      _store.saveLastEpisodes(_lastEpisodeBySeries),
    ]);
  }

  Future<void> removeFromContinueWatching(MediaItem item) async {
    _progress.remove(item.id);
    final episodeId = _lastEpisodeBySeries.remove(item.id);
    if (episodeId != null) _episodeProgress.remove(episodeId);
    _history.remove(item.id);
    _recommendationsCache = null;
    notifyListeners();
    await _savePlaybackActivity();
  }

  Future<void> clearContinueWatching() async {
    final activeIds = _progress.entries
        .where((entry) => entry.value > 0 && entry.value < 0.95)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final id in activeIds) {
      _progress.remove(id);
      final episodeId = _lastEpisodeBySeries.remove(id);
      if (episodeId != null) _episodeProgress.remove(episodeId);
    }
    _recommendationsCache = null;
    notifyListeners();
    await _savePlaybackActivity();
  }

  Future<void> clearPlaybackHistory() async {
    _progress.clear();
    _episodeProgress.clear();
    _lastEpisodeBySeries.clear();
    _history.clear();
    _recommendationsCache = null;
    notifyListeners();
    await _savePlaybackActivity();
  }

  Future<void> resetMovieProgress() async {
    final movieIds = _catalog
        .where((item) => item.type == MediaType.movie)
        .map((item) => item.id)
        .toSet();
    _progress.removeWhere((id, _) => movieIds.contains(id));
    _history.removeWhere((id) => movieIds.contains(id));
    _recommendationsCache = null;
    notifyListeners();
    await _savePlaybackActivity();
  }

  Future<void> resetSeriesProgress() async {
    final seriesIds = _catalog
        .where((item) => item.type == MediaType.series)
        .map((item) => item.id)
        .toSet();
    _progress.removeWhere((id, _) => seriesIds.contains(id));
    _history.removeWhere((id) => seriesIds.contains(id));
    _episodeProgress.clear();
    _lastEpisodeBySeries.clear();
    _recommendationsCache = null;
    notifyListeners();
    await _savePlaybackActivity();
  }

  Future<void> _savePlaybackActivity() async {
    await Future.wait([
      _store.saveProgress(_progress),
      _store.saveEpisodeProgress(_episodeProgress),
      _store.saveLastEpisodes(_lastEpisodeBySeries),
      _store.saveHistory(_history),
    ]);
  }

  OfflineDownload? downloadForMovie(MediaItem item) =>
      _downloadById('movie-${item.id}');

  OfflineDownload? downloadForEpisode(EpisodeItem episode) =>
      _downloadById('episode-${episode.id}');

  OfflineDownload? _downloadById(String id) {
    for (final item in _downloads) {
      if (item.id == id) return item;
    }
    return null;
  }

  bool isDownloading(String id) => _activeDownloads.contains(id);
  double downloadProgress(String id) => _downloadProgress[id] ?? 0;

  Future<String?> downloadMovie(MediaItem item) async {
    final id = 'movie-${item.id}';
    if (_activeDownloads.contains(id)) return null;
    _activeDownloads.add(id);
    _downloadProgress[id] = 0;
    notifyListeners();
    try {
      final downloaded = await _downloadService.download(
        id: id,
        sourceMediaId: item.id,
        title: item.title,
        subtitle: 'Película',
        posterUrl: item.posterUrl,
        urls: item.streamUrls,
        onProgress: (value) => _setDownloadProgress(id, value),
      );
      _downloads.removeWhere((entry) => entry.id == id);
      _downloads.insert(0, downloaded);
      return null;
    } on DownloadException catch (error) {
      return error.message;
    } catch (_) {
      return 'No se pudo descargar la película.';
    } finally {
      _activeDownloads.remove(id);
      _downloadProgress.remove(id);
      notifyListeners();
    }
  }

  Future<String?> downloadEpisode(
    MediaItem series,
    EpisodeItem episode,
  ) async {
    final id = 'episode-${episode.id}';
    if (_activeDownloads.contains(id)) return null;
    _activeDownloads.add(id);
    _downloadProgress[id] = 0;
    notifyListeners();
    try {
      final downloaded = await _downloadService.download(
        id: id,
        sourceMediaId: series.id,
        title: series.title,
        subtitle: '${episode.numberLabel} • ${episode.title}',
        posterUrl:
            episode.imageUrl.isEmpty ? series.posterUrl : episode.imageUrl,
        urls: episode.streamUrls,
        episodeId: episode.id,
        onProgress: (value) => _setDownloadProgress(id, value),
      );
      _downloads.removeWhere((entry) => entry.id == id);
      _downloads.insert(0, downloaded);
      return null;
    } on DownloadException catch (error) {
      return error.message;
    } catch (_) {
      return 'No se pudo descargar el episodio.';
    } finally {
      _activeDownloads.remove(id);
      _downloadProgress.remove(id);
      notifyListeners();
    }
  }

  void cancelDownload(String id) {
    _downloadService.cancel(id);
  }

  Future<void> removeDownload(OfflineDownload item) async {
    await _downloadService.remove(item);
    _downloads.removeWhere((entry) => entry.id == item.id);
    notifyListeners();
  }

  void _setDownloadProgress(String id, double value) {
    final previous = _downloadProgress[id] ?? -1;
    if ((value - previous).abs() < 0.02 && value < 1) return;
    _downloadProgress[id] = value;
    notifyListeners();
  }

  List<MediaItem> get movies => UnmodifiableListView(_movies);

  List<MediaItem> get series => UnmodifiableListView(_series);

  List<MediaItem> get liveChannels => UnmodifiableListView(_liveChannels);

  List<String> get liveCategories => UnmodifiableListView(_liveCategoryNames);

  List<MediaItem> get recentlyAdded => UnmodifiableListView(_recentlyAdded);

  List<MediaItem> get myList => _favorites
      .map(findById)
      .whereType<MediaItem>()
      .toList(growable: false);

  List<MediaItem> get continueWatching => _progress.entries
      .where((entry) => entry.value > 0 && entry.value < 0.95)
      .map((entry) => findById(entry.key))
      .whereType<MediaItem>()
      .where((item) => !item.isLive)
      .toList(growable: false)
    ..sort((a, b) {
      final aIndex = _history.indexOf(a.id);
      final bIndex = _history.indexOf(b.id);
      return (aIndex < 0 ? 9999 : aIndex)
          .compareTo(bIndex < 0 ? 9999 : bIndex);
    });

  List<MediaItem> get recentlyWatched => _history
      .map(findById)
      .whereType<MediaItem>()
      .where((item) => !item.isLive)
      .toList(growable: false);

  List<MediaItem> get recentlyWatchedLive => _history
      .map(findById)
      .whereType<MediaItem>()
      .where((item) => item.isLive)
      .toList(growable: false);

  List<MediaItem> get completedMovies => _progress.entries
      .where((entry) => entry.value >= 0.95)
      .map((entry) => findById(entry.key))
      .whereType<MediaItem>()
      .where((item) => item.type == MediaType.movie)
      .toList(growable: false)
    ..sort((a, b) {
      final aIndex = _history.indexOf(a.id);
      final bIndex = _history.indexOf(b.id);
      return (aIndex < 0 ? 9999 : aIndex)
          .compareTo(bIndex < 0 ? 9999 : bIndex);
    });

  List<MediaItem> get seriesInProgress => continueWatching
      .where((item) => item.type == MediaType.series)
      .toList(growable: false);

  bool get hasPlaybackActivity =>
      _history.isNotEmpty ||
      _progress.values.any((value) => value > 0) ||
      _episodeProgress.values.any((value) => value > 0);

  List<MediaItem> get recommendations {
    final cached = _recommendationsCache;
    if (cached != null) return cached;

    final candidates = _catalog.where((item) => !item.isLive).toList();
    final watched = _history.map(findById).whereType<MediaItem>().toList();
    if (watched.isEmpty) {
      final sorted = List<MediaItem>.from(candidates)
        ..sort((a, b) => b.rating.compareTo(a.rating));
      return _recommendationsCache =
          List<MediaItem>.unmodifiable(sorted.take(40));
    }

    final genreWeights = <String, int>{};
    final castWeights = <String, int>{};
    final franchiseWeights = <String, int>{};

    for (var index = 0; index < watched.length; index++) {
      final item = watched[index];
      final recencyWeight = math.max(1, 7 - index).toInt();
      for (final genre in item.genres) {
        genreWeights.update(
          genre.toLowerCase(),
          (value) => value + recencyWeight,
          ifAbsent: () => recencyWeight,
        );
      }
      for (final person in item.cast.take(4)) {
        castWeights.update(
          person.toLowerCase(),
          (value) => value + 2,
          ifAbsent: () => 2,
        );
      }
      final franchise = item.franchise?.toLowerCase();
      if (franchise != null && franchise.isNotEmpty) {
        franchiseWeights.update(
          franchise,
          (value) => value + 12,
          ifAbsent: () => 12,
        );
      }
    }

    final scored = candidates.map((item) {
      var score = item.rating;
      for (final genre in item.genres) {
        score += (genreWeights[genre.toLowerCase()] ?? 0) * 1.7;
      }
      for (final person in item.cast) {
        score += (castWeights[person.toLowerCase()] ?? 0) * 1.2;
      }
      final franchise = item.franchise?.toLowerCase();
      if (franchise != null) score += franchiseWeights[franchise] ?? 0;
      final itemRoot = _titleRoot(item.title);
      for (final watchedItem in watched.take(8)) {
        final watchedRoot = _titleRoot(watchedItem.title);
        if (itemRoot.length >= 4 && itemRoot == watchedRoot) score += 32;
        if (itemRoot.length >= 4 && itemRoot.startsWith(watchedRoot)) score += 14;
      }
      if (item.isNew) score += 2.5;
      if ((_progress[item.id] ?? 0) >= 0.95) score -= 20;
      return (item: item, score: score);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return _recommendationsCache = List<MediaItem>.unmodifiable(
      scored.map((entry) => entry.item).take(50),
    );
  }

  CatalogSearchResult searchResult(
    String query, {
    MediaType? type,
    int limit = 280,
  }) {
    if (query.trim().isEmpty && type == null) {
      return CatalogSearchResult(
        items: <MediaItem>[
          ...recommendations,
          ...liveChannels.take(20),
        ].take(limit).toList(growable: false),
      );
    }
    return _catalogSearch.search(query, type: type, limit: limit);
  }

  List<MediaItem> search(
    String query, {
    MediaType? type,
    int limit = 280,
  }) =>
      searchResult(query, type: type, limit: limit).items;

  void _setCatalog(List<MediaItem> items) {
    _catalog = List<MediaItem>.unmodifiable(items);
    _movies = List<MediaItem>.unmodifiable(
      _catalog.where((item) => item.type == MediaType.movie),
    );
    _series = List<MediaItem>.unmodifiable(
      _catalog.where((item) => item.type == MediaType.series),
    );
    _liveChannels = List<MediaItem>.unmodifiable(
      _catalog.where((item) => item.type == MediaType.live),
    );
    final categories = _liveChannels
        .expand((item) => item.genres)
        .where((value) => value.trim().isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _liveCategoryNames = List<String>.unmodifiable(categories);

    final fresh = _catalog
        .where((item) => item.type != MediaType.live && item.isNew)
        .toList()
      ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
    if (fresh.isNotEmpty) {
      _recentlyAdded = List<MediaItem>.unmodifiable(fresh.take(80));
    } else {
      final fallback = _catalog.where((item) => !item.isLive).toList()
        ..sort((a, b) => b.addedAt.compareTo(a.addedAt));
      _recentlyAdded = List<MediaItem>.unmodifiable(fallback.take(40));
    }
    _recommendationsCache = null;

    _itemsById = Map<String, MediaItem>.unmodifiable({
      for (final item in _catalog) item.id: item,
    });
    _catalogSearch.replaceCatalog(_catalog);
  }

  String _titleRoot(String raw) {
    var value = raw.toLowerCase();
    value = value.replaceAll(RegExp(r'\([^)]*\)|\[[^]]*\]'), ' ');
    value = value.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
    value = value.replaceAll(
      RegExp(r'\b(parte|part|temporada|season|capitulo|capítulo|episodio)\s*[0-9ivx]+\b'),
      ' ',
    );
    value = value.replaceAll(RegExp(r'\b[ivx]{1,5}\b|\b\d+\b'), ' ');
    value = value.replaceAll(RegExp(r'[^a-z0-9áéíóúüñ]+'), ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _catalogWasUpdatedToday() {
    final previous = _lastCatalogRefresh;
    final now = DateTime.now();
    return previous != null &&
        previous.year == now.year &&
        previous.month == now.month &&
        previous.day == now.day;
  }

  String _profileName(LoginCredentials credentials) {
    final value = credentials.profileName.trim();
    return value.isNotEmpty ? value : credentials.username;
  }

  List<MediaItem> _buildDemoCatalog() {
    const sampleVideo =
        'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
    const sampleLive =
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8';
    final items = demoCatalog.map((item) {
      return MediaItem(
        id: item.id,
        providerId: item.providerId,
        title: item.title,
        type: item.type,
        year: item.year,
        rating: item.rating,
        description: item.description,
        posterUrl: item.posterUrl,
        backdropUrl: item.backdropUrl,
        genres: item.genres,
        cast: item.cast,
        keywords: item.keywords,
        durationLabel: item.durationLabel,
        franchise: item.franchise,
        isNew: item.isNew,
        addedAt: item.addedAt,
        trailerUrl: item.trailerUrl,
        streamUrls: item.type == MediaType.movie ? const [sampleVideo] : const [],
      );
    }).toList();
    items.insert(
      0,
      const MediaItem(
        id: 'live-demo',
        providerId: 'demo',
        title: 'Canal de demostración',
        type: MediaType.live,
        year: 2026,
        rating: 0,
        description: 'Transmisión HLS pública para comprobar el reproductor en vivo.',
        posterUrl: '',
        backdropUrl: '',
        genres: ['Demostración'],
        cast: [],
        keywords: ['canal', 'demo', 'en vivo'],
        durationLabel: 'EN VIVO',
        streamUrls: [sampleLive],
      ),
    );
    return items;
  }

  SeriesDetails _demoSeriesDetails(MediaItem series) {
    const sampleVideo =
        'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4';
    final seasons = <int, List<EpisodeItem>>{};
    for (var season = 1; season <= 2; season++) {
      seasons[season] = List.generate(4, (index) {
        final episode = index + 1;
        return EpisodeItem(
          id: '${series.id}-s$season-e$episode',
          title: 'Episodio $episode',
          seasonNumber: season,
          episodeNumber: episode,
          description:
              'Episodio de demostración para probar el reproductor y el progreso.',
          durationLabel: 'Demo',
          imageUrl: series.backdropUrl,
          streamUrls: const [sampleVideo],
          rating: series.rating,
        );
      });
    }
    return SeriesDetails(seriesId: series.id, seasons: seasons);
  }

  @override
  void dispose() {
    _recordingRefreshTimer?.cancel();
    _api.dispose();
    _downloadService.dispose();
    super.dispose();
  }
}
