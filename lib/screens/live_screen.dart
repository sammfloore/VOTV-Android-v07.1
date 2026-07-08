import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/app_theme.dart';
import '../models/media_item.dart';
import '../models/player_launch_payload.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../widgets/network_art.dart';
import 'video_player_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  static const _allCategory = '__all__';
  static const _favoritesCategory = '__favorites__';
  static const _historyCategory = '__history__';
  static const _httpHeaders = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 AVO-TV/0.7.1',
    'Accept': '*/*',
  };

  final _searchController = TextEditingController();
  final _channelScrollController = ScrollController();
  final _previewPlayer = Player(
    configuration: const PlayerConfiguration(bufferSize: 32 * 1024 * 1024),
  );
  late final VideoController _previewVideoController;
  final List<StreamSubscription<dynamic>> _previewSubscriptions = [];

  Timer? _searchDebounce;
  Timer? _previewAutoStopTimer;
  String _query = '';
  String _category = _allCategory;
  MediaItem? _selectedChannel;
  bool _previewLoading = false;
  bool _previewPlaying = false;
  bool _previewMuted = true;
  String? _previewError;
  int _previewGeneration = 0;
  bool _switchingChannel = false;

  @override
  void initState() {
    super.initState();
    _previewVideoController = VideoController(_previewPlayer);
    _previewSubscriptions.add(
      _previewPlayer.stream.playing.listen((value) {
        if (mounted) setState(() => _previewPlaying = value);
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.state.liveChannels.isEmpty) return;
      setState(() => _selectedChannel = widget.state.liveChannels.first);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _previewAutoStopTimer?.cancel();
    _searchController.dispose();
    _channelScrollController.dispose();
    for (final subscription in _previewSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_disposePreviewPlayer());
    super.dispose();
  }


  Future<void> _disposePreviewPlayer() async {
    try {
      await _previewPlayer.setVolume(0);
    } catch (_) {}
    try {
      await _previewPlayer.pause();
    } catch (_) {}
    try {
      await _previewPlayer.stop();
    } catch (_) {}
    try {
      await _previewPlayer.dispose();
    } catch (_) {}
  }

  List<MediaItem> get _visibleChannels {
    final searched = widget.state.search(
      _query,
      type: MediaType.live,
      limit: widget.state.liveChannels.length + 1,
    );
    return searched.where((item) {
      switch (_category) {
        case _favoritesCategory:
          return widget.state.isFavorite(item);
        case _historyCategory:
          return widget.state.history.contains(item.id);
        case _allCategory:
          return true;
        default:
          return item.genres.contains(_category);
      }
    }).toList(growable: false);
  }

  List<_LiveCategoryEntry> get _categoryEntries => [
        _LiveCategoryEntry(
          id: _allCategory,
          label: 'Todos los canales',
          icon: Icons.live_tv_rounded,
          count: widget.state.liveChannels.length,
        ),
        _LiveCategoryEntry(
          id: _favoritesCategory,
          label: 'Favoritos',
          icon: Icons.star_rounded,
          count: widget.state.liveChannels
              .where(widget.state.isFavorite)
              .length,
        ),
        _LiveCategoryEntry(
          id: _historyCategory,
          label: 'Vistos recientemente',
          icon: Icons.history_rounded,
          count: widget.state.recentlyWatchedLive.length,
        ),
        ...widget.state.liveCategories.map(
          (category) => _LiveCategoryEntry(
            id: category,
            label: category,
            icon: _categoryIcon(category),
            count: widget.state.liveChannels
                .where((item) => item.genres.contains(category))
                .length,
          ),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1120;
        final medium = constraints.maxWidth >= 760;
        final channels = _visibleChannels;
        _repairSelectedChannel(channels);

        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: AppBar(
            backgroundColor: AppTheme.background,
            scrolledUnderElevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Televisión en vivo',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '${widget.state.liveChannels.length} canales disponibles',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            actions: [
              if (widget.state.activeRecording != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Center(
                    child: Tooltip(
                      message: 'Grabando ${widget.state.activeRecording!.title}',
                      child: const _RecordingBadge(),
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Buscar canal',
                onPressed: () => _showSearch(context),
                icon: const Icon(Icons.search_rounded),
              ),
              if (!widget.state.isDemo)
                IconButton(
                  tooltip: 'Actualizar catálogo',
                  onPressed: widget.state.isRefreshingCatalog
                      ? null
                      : () => _refreshCatalog(context),
                  icon: widget.state.isRefreshingCatalog
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : const Icon(Icons.sync_rounded),
                ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: wide
                ? _buildWideLayout(channels)
                : medium
                    ? _buildMediumLayout(channels)
                    : _buildCompactLayout(channels),
          ),
        );
      },
    );
  }

  Widget _buildWideLayout(List<MediaItem> channels) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 270, child: _buildCategoryPane()),
          const SizedBox(width: 14),
          SizedBox(width: 380, child: _buildChannelPane(channels)),
          const SizedBox(width: 14),
          Expanded(child: _buildPreviewPane()),
        ],
      ),
    );
  }

  Widget _buildMediumLayout(List<MediaItem> channels) {
    return Column(
      children: [
        _buildHorizontalCategories(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Row(
              children: [
                SizedBox(width: 330, child: _buildChannelPane(channels)),
                const SizedBox(width: 14),
                Expanded(child: _buildPreviewPane()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(List<MediaItem> channels) {
    return CustomScrollView(
      key: const PageStorageKey<String>('live-premium-catalog'),
      slivers: [
        SliverToBoxAdapter(child: _buildHorizontalCategories()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            child: SizedBox(height: 320, child: _buildPreviewPane()),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedCategoryLabel,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                Text(
                  '${channels.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (channels.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyLiveState(),
          )
        else
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  index == 0 ? 0 : 4,
                  14,
                  index == channels.length - 1 ? 28 : 4,
                ),
                child: _ChannelTile(
                  item: channels[index],
                  state: widget.state,
                  selected: channels[index].id == _selectedChannel?.id,
                  onTap: () => _selectChannel(channels[index]),
                  onFavorite: () => _toggleFavorite(channels[index]),
                ),
              ),
              childCount: channels.length,
            ),
          ),
      ],
    );
  }

  Widget _buildCategoryPane() {
    final entries = _categoryEntries;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar canales',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: Text(
              'CATEGORÍAS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.48),
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _CategoryTile(
                  entry: entry,
                  selected: entry.id == _category,
                  onTap: () => _selectCategory(entry.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCategories() {
    return SizedBox(
      height: 62,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        scrollDirection: Axis.horizontal,
        itemCount: _categoryEntries.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final entry = _categoryEntries[index];
          return ChoiceChip(
            selected: entry.id == _category,
            avatar: Icon(entry.icon, size: 18),
            label: Text('${entry.label}  ${entry.count}'),
            onSelected: (_) => _selectCategory(entry.id),
          );
        },
      ),
    );
  }

  Widget _buildChannelPane(List<MediaItem> channels) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedCategoryLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                _CountBadge(count: channels.length),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
          Expanded(
            child: channels.isEmpty
                ? const _EmptyLiveState()
                : ListView.builder(
                    controller: _channelScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: channels.length,
                    itemBuilder: (context, index) {
                      final item = channels[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: _ChannelTile(
                          item: item,
                          state: widget.state,
                          selected: item.id == _selectedChannel?.id,
                          autofocus:
                              index == 0 && widget.state.isTelevision,
                          onTap: () => _selectChannel(item),
                          onFavorite: () => _toggleFavorite(item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPane() {
    final channel = _selectedChannel;
    return _Panel(
      child: channel == null
          ? const _EmptyPreviewState()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: Colors.black,
                          child: _previewPlaying || _previewLoading
                              ? Video(
                                  controller: _previewVideoController,
                                  controls: NoVideoControls,
                                  fit: BoxFit.contain,
                                  fill: Colors.black,
                                  wakelock: true,
                                  pauseUponEnteringBackgroundMode: true,
                                )
                              : NetworkArt(
                                  url: channel.backdropUrl.isNotEmpty
                                      ? channel.backdropUrl
                                      : channel.posterUrl,
                                  fit: BoxFit.contain,
                                  fallbackLabel: channel.title,
                                  live: true,
                                ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x22000000),
                                Color(0x08000000),
                                Color(0xC9000000),
                              ],
                              stops: [0, 0.58, 1],
                            ),
                          ),
                        ),
                        const Positioned(
                          left: 16,
                          top: 16,
                          child: _LiveBadge(),
                        ),
                        if (_previewLoading)
                          const Center(child: CircularProgressIndicator()),
                        if (_previewError != null)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.signal_wifi_connected_no_internet_4_rounded,
                                    size: 52,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'La vista previa no respondió',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: () => _startPreview(channel),
                                    icon: const Icon(Icons.refresh_rounded),
                                    label: const Text('Reintentar'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 16,
                          child: Row(
                            children: [
                              IconButton.filledTonal(
                                tooltip: _previewPlaying
                                    ? 'Pausar vista previa'
                                    : 'Reproducir vista previa',
                                onPressed: _previewLoading
                                    ? null
                                    : () => _togglePreview(channel),
                                icon: Icon(
                                  _previewPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              IconButton.filledTonal(
                                tooltip:
                                    _previewMuted ? 'Activar sonido' : 'Silenciar',
                                onPressed: _previewPlaying ? _togglePreviewMute : null,
                                icon: Icon(
                                  _previewMuted
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _buildRecordingButton(channel),
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _switchingChannel
                                    ? null
                                    : () => _openChannel(channel),
                                icon: const Icon(Icons.fullscreen_rounded),
                                label: Text(
                                  _switchingChannel
                                      ? 'Cambiando…'
                                      : 'Ver canal',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 82,
                        height: 58,
                        child: NetworkArt(
                          url: channel.posterUrl,
                          fit: BoxFit.contain,
                          borderRadius: BorderRadius.circular(12),
                          fallbackLabel: channel.title,
                          live: true,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              channel.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: widget.state.isTelevision ? 23 : 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              channel.genres.isEmpty
                                  ? 'Canal en vivo'
                                  : channel.genres.join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: widget.state.isFavorite(channel)
                            ? 'Quitar de favoritos'
                            : 'Agregar a favoritos',
                        onPressed: () => _toggleFavorite(channel),
                        icon: Icon(
                          widget.state.isFavorite(channel)
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: widget.state.isFavorite(channel)
                              ? const Color(0xFFFFD166)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  String get _selectedCategoryLabel {
    switch (_category) {
      case _favoritesCategory:
        return 'Favoritos';
      case _historyCategory:
        return 'Vistos recientemente';
      case _allCategory:
        return 'Todos los canales';
      default:
        return _category;
    }
  }

  void _repairSelectedChannel(List<MediaItem> channels) {
    final selected = _selectedChannel;
    if (channels.isEmpty ||
        (selected != null && channels.any((item) => item.id == selected.id))) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _selectedChannel = channels.first);
    });
  }

  void _selectCategory(String category) {
    if (_category == category) return;
    unawaited(_stopPreview());
    setState(() {
      _category = category;
      _previewError = null;
      _previewPlaying = false;
      _selectedChannel = null;
    });
  }

  Future<void> _selectChannel(MediaItem item) async {
    if (_switchingChannel) return;
    final alreadySelected = _selectedChannel?.id == item.id;
    setState(() {
      _selectedChannel = item;
      _previewError = null;
    });

    final activePlayer = await PlatformService.hasActivePlayer();
    if (!mounted) return;
    if (activePlayer) {
      await _openChannel(item, fromChannelSelection: true);
      return;
    }

    // Para TV en vivo estable evitamos abrir una conexión de vista previa con
    // cada toque. La señal solo se carga cuando el usuario pulsa reproducir
    // vista previa o Ver canal, reduciendo saturación, audio duplicado y
    // bloqueos en cuentas con pocas conexiones simultáneas.
    if (!alreadySelected || _previewPlaying || _previewLoading) {
      await _stopPreview();
    }
  }

  Future<void> _startPreview(MediaItem item) async {
    final generation = ++_previewGeneration;
    await _previewPlayer.stop();
    if (!mounted || generation != _previewGeneration) return;
    setState(() {
      _previewLoading = true;
      _previewPlaying = false;
      _previewError = null;
    });

    final candidates = item.streamUrls
        .map((url) => url.trim())
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (candidates.isEmpty) {
      if (mounted && generation == _previewGeneration) {
        setState(() {
          _previewLoading = false;
          _previewError = 'Este canal no incluye una señal reproducible.';
        });
      }
      return;
    }

    for (final resource in candidates) {
      if (generation != _previewGeneration) return;
      try {
        await _previewPlayer.open(
          Media(resource, httpHeaders: _httpHeaders),
          play: true,
        );
        await _previewPlayer.setVolume(
          _previewMuted
              ? 0
              : widget.state.playbackVolume.clamp(0, 100).toDouble(),
        );
        var ready = false;
        for (var attempt = 0; attempt < 35; attempt++) {
          if (generation != _previewGeneration) return;
          final state = _previewPlayer.state;
          if (state.playing && !state.buffering) {
            ready = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 180));
        }
        if (!ready) {
          await _previewPlayer.stop();
          continue;
        }
        if (!mounted || generation != _previewGeneration) return;
        _previewAutoStopTimer?.cancel();
        _previewAutoStopTimer = Timer(const Duration(seconds: 45), () {
          if (mounted && _previewPlaying) unawaited(_stopPreview());
        });
        setState(() {
          _previewLoading = false;
          _previewPlaying = true;
          _previewError = null;
        });
        return;
      } catch (_) {
        await _previewPlayer.stop();
      }
    }

    if (!mounted || generation != _previewGeneration) return;
    setState(() {
      _previewLoading = false;
      _previewPlaying = false;
      _previewError = 'No se pudo cargar ninguna señal de este canal.';
    });
  }

  Future<void> _stopPreview() async {
    _previewAutoStopTimer?.cancel();
    _previewAutoStopTimer = null;
    _previewGeneration++;
    try {
      await _previewPlayer.setVolume(0);
      await _previewPlayer.pause();
      await _previewPlayer.stop();
    } catch (_) {
      // La vista previa es secundaria; nunca debe bloquear el reproductor principal.
    }
    if (mounted) {
      setState(() {
        _previewLoading = false;
        _previewPlaying = false;
      });
    }
  }

  Future<void> _togglePreview(MediaItem channel) async {
    if (_previewPlaying) {
      await _previewPlayer.pause();
    } else if (_previewPlayer.state.position > Duration.zero) {
      await _previewPlayer.play();
    } else {
      await _startPreview(channel);
    }
  }

  Future<void> _togglePreviewMute() async {
    _previewMuted = !_previewMuted;
    await _previewPlayer.setVolume(
      _previewMuted
          ? 0
          : widget.state.playbackVolume.clamp(0, 100).toDouble(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openChannel(
    MediaItem item, {
    bool fromChannelSelection = false,
  }) async {
    if (_switchingChannel) return;
    if (item.streamUrls.where((url) => url.trim().isNotEmpty).isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este canal no incluye señal reproducible.')),
      );
      return;
    }

    setState(() => _switchingChannel = true);
    var opened = false;
    try {
      await _stopPreview();
      await widget.state.markLiveChannelOpened(item);

      opened = await PlatformService.openPlayer(
        PlayerLaunchPayload(
          title: item.title,
          subtitle: item.genres.isEmpty
              ? 'Televisión en vivo'
              : item.genres.first,
          urls: item.streamUrls,
          isLive: true,
          previewImageUrl:
              item.backdropUrl.isNotEmpty ? item.backdropUrl : item.posterUrl,
          mediaItem: item,
        ).toJson(),
        bringToFront: !fromChannelSelection,
      );
    } finally {
      if (mounted) setState(() => _switchingChannel = false);
    }

    if (!mounted) return;
    if (opened) {
      if (fromChannelSelection) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(milliseconds: 1400),
            content: Text('Cambiando a ${item.title}…'),
          ),
        );
      }
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          appState: widget.state,
          title: item.title,
          subtitle: item.genres.isEmpty ? null : item.genres.first,
          urls: item.streamUrls,
          isLive: true,
          previewImageUrl:
              item.backdropUrl.isNotEmpty ? item.backdropUrl : item.posterUrl,
          liveChannelId: item.id,
        ),
      ),
    );
  }


  Widget _buildRecordingButton(MediaItem channel) {
    final active = widget.state.activeRecording;
    final sameChannel = active?.sourceChannelId == channel.id;
    final capability = widget.state.recordingCapability;
    return IconButton.filledTonal(
      tooltip: active == null
          ? 'Grabar canal'
          : sameChannel
              ? 'Detener grabación'
              : 'Ya se está grabando ${active.title}',
      onPressed: capability.supported || active != null
          ? () => _handleRecording(channel)
          : () => _showRecordingUnavailable(capability.reason),
      icon: Icon(
        sameChannel ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
        color: active == null || sameChannel ? Colors.redAccent : Colors.orangeAccent,
      ),
    );
  }

  Future<void> _handleRecording(MediaItem channel) async {
    await widget.state.refreshRecordings();
    if (!mounted) return;
    final active = widget.state.activeRecording;
    if (active != null) {
      if (active.sourceChannelId == channel.id) {
        await _confirmStopRecording(active.title);
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Grabación en curso'),
            content: Text(
              'AVO TV está grabando “${active.title}” en segundo plano. Puedes ver este canal o cualquier otro contenido, pero solo se permite una grabación a la vez.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Entendido'),
              ),
              FilledButton.tonal(
                onPressed: () async {
                  Navigator.pop(context);
                  await _confirmStopRecording(active.title);
                },
                child: const Text('Detener grabación'),
              ),
            ],
          ),
        );
      }
      return;
    }
    final capability = widget.state.recordingCapability;
    if (!capability.supported) {
      _showRecordingUnavailable(capability.reason);
      return;
    }
    await _showStartRecordingDialog(channel);
  }

  Future<void> _showStartRecordingDialog(MediaItem channel) async {
    final controller = TextEditingController(text: channel.title);
    var durationMinutes = 180;
    final selection = await showDialog<({String title, int minutes})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Grabar televisión en vivo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  channel.title,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la grabación',
                    hintText: 'Ejemplo: México vs. Argentina',
                    prefixIcon: Icon(Icons.edit_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: durationMinutes,
                  decoration: const InputDecoration(
                    labelText: 'Duración máxima',
                    prefixIcon: Icon(Icons.timer_outlined),
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
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.055),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(13),
                    child: Text(
                      '${_formatStorage(widget.state.recordingCapability.availableBytes)} disponibles. La grabación continuará aunque abras otro canal, película, serie o aplicación. Esto utiliza una conexión adicional de tu cuenta.',
                      style: TextStyle(
                        height: 1.4,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
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
    await _stopPreview();
    if (!mounted) return;
    final error = await widget.state.startLiveRecording(
      sourceChannelId: channel.id,
      title: selection.title,
      channelTitle: channel.title,
      posterUrl: channel.posterUrl,
      urls: channel.streamUrls,
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
    if (error != null &&
        error.toLowerCase().contains('notificaciones')) {
      await _offerNotificationSettings();
    }
  }

  Future<void> _confirmStopRecording(String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detener grabación'),
        content: Text(
          '¿Deseas finalizar “$title”? El video guardado permanecerá en Mis grabaciones.',
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
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Grabación guardada correctamente.')),
    );
  }

  void _showRecordingUnavailable(String reason) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grabación no disponible'),
        content: Text(
          reason.isEmpty
              ? 'Este dispositivo no cumple los requisitos de almacenamiento para grabar.'
              : reason,
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

  Future<void> _offerNotificationSettings() async {
    if (!mounted) return;
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permitir notificaciones'),
        content: const Text(
          'La notificación permite comprobar la grabación y detenerla aun cuando AVO TV esté en segundo plano.',
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
    if (open == true) {
      await PlatformService.openRecordingNotificationSettings();
    }
  }

  String _formatStorage(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    await widget.state.toggleFavorite(item);
    if (mounted) setState(() {});
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() => _query = '');
  }

  Future<void> _showSearch(BuildContext context) async {
    final controller = TextEditingController(text: _searchController.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppTheme.surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: TextField(
          autofocus: true,
          controller: controller,
          onChanged: (value) {
            _searchController.text = value;
            _searchController.selection = TextSelection.collapsed(
              offset: value.length,
            );
            _onSearchChanged(value);
          },
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Buscar canal',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
      ),
    );
    controller.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _refreshCatalog(BuildContext context) async {
    final ok = await widget.state.refreshCatalog();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          widget.state.catalogMessage ??
              (ok ? 'Catálogo actualizado.' : 'No se pudo actualizar.'),
        ),
      ),
    );
  }

  static IconData _categoryIcon(String category) {
    final value = category.toLowerCase();
    if (value.contains('deport') || value.contains('sport')) {
      return Icons.sports_soccer_rounded;
    }
    if (value.contains('notic') || value.contains('news')) {
      return Icons.newspaper_rounded;
    }
    if (value.contains('infantil') || value.contains('kids')) {
      return Icons.child_care_rounded;
    }
    if (value.contains('película') || value.contains('movie')) {
      return Icons.movie_rounded;
    }
    if (value.contains('música') || value.contains('music')) {
      return Icons.music_note_rounded;
    }
    if (value.contains('evento')) return Icons.event_available_rounded;
    return Icons.folder_copy_rounded;
  }
}


class _RecordingBadge extends StatelessWidget {
  const _RecordingBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.55)),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fiber_manual_record_rounded, color: Colors.redAccent, size: 14),
            SizedBox(width: 5),
            Text('REC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Color(0x44000000), blurRadius: 26, offset: Offset(0, 12)),
        ],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(22), child: child),
    );
  }
}

class _LiveCategoryEntry {
  const _LiveCategoryEntry({
    required this.id,
    required this.label,
    required this.icon,
    required this.count,
  });

  final String id;
  final String label;
  final IconData icon;
  final int count;
}

class _CategoryTile extends StatefulWidget {
  const _CategoryTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final _LiveCategoryEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _focused;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: widget.selected
            ? AppTheme.accent.withValues(alpha: 0.16)
            : highlighted
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          autofocus: widget.autofocus,
          borderRadius: BorderRadius.circular(14),
          onFocusChange: (value) => setState(() => _focused = value),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(
                  widget.entry.icon,
                  color: widget.selected ? AppTheme.accent : null,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight:
                          widget.selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.entry.count}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.48),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({
    required this.item,
    required this.state,
    required this.selected,
    required this.onTap,
    required this.onFavorite,
    this.autofocus = false,
  });

  final MediaItem item;
  final AppState state;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final bool autofocus;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final highlighted = widget.selected || _focused;
    return Material(
      color: widget.selected
          ? AppTheme.accent.withValues(alpha: 0.14)
          : highlighted
              ? Colors.white.withValues(alpha: 0.065)
              : Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(16),
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          if (focused && widget.state.isTelevision) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 180),
                alignment: 0.28,
              );
            });
          }
        },
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: highlighted
                  ? AppTheme.accent.withValues(alpha: widget.selected ? 0.85 : 0.5)
                  : Colors.white.withValues(alpha: 0.05),
              width: highlighted ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 88,
                height: 54,
                child: NetworkArt(
                  url: widget.item.posterUrl,
                  fit: BoxFit.contain,
                  borderRadius: BorderRadius.circular(10),
                  fallbackLabel: widget.item.title,
                  live: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.item.genres.isEmpty
                          ? 'Canal en vivo'
                          : widget.item.genres.first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: widget.state.isFavorite(widget.item)
                    ? 'Quitar de favoritos'
                    : 'Agregar a favoritos',
                onPressed: widget.onFavorite,
                icon: Icon(
                  widget.state.isFavorite(widget.item)
                      ? Icons.star_rounded
                      : Icons.star_border_rounded,
                  size: 21,
                  color: widget.state.isFavorite(widget.item)
                      ? const Color(0xFFFFD166)
                      : Colors.white.withValues(alpha: 0.62),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE64545),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: Colors.white),
            SizedBox(width: 6),
            Text(
              'EN VIVO',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          '$count',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
        ),
      ),
    );
  }
}

class _EmptyLiveState extends StatelessWidget {
  const _EmptyLiveState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.live_tv_outlined,
              size: 56,
              color: Colors.white.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 14),
            const Text(
              'No hay canales en esta sección',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPreviewState extends StatelessWidget {
  const _EmptyPreviewState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.ondemand_video_rounded,
              size: 70,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 18),
            const Text(
              'Selecciona un canal',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'La señal aparecerá aquí antes de abrirla en pantalla completa.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.52)),
            ),
          ],
        ),
      ),
    );
  }
}
