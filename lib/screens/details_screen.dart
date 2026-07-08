import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/media_item.dart';
import '../models/player_launch_payload.dart';
import '../models/series_details.dart';
import '../services/platform_service.dart';
import '../state/app_state.dart';
import '../widgets/media_row.dart';
import '../widgets/network_art.dart';
import 'video_player_screen.dart';

class DetailsScreen extends StatefulWidget {
  const DetailsScreen({
    super.key,
    required this.item,
    required this.state,
  });

  final MediaItem item;
  final AppState state;

  @override
  State<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends State<DetailsScreen> {
  Future<SeriesDetails>? _seriesFuture;
  SeriesDetails? _loadedSeries;
  int? _selectedSeason;
  _DetailsContentTab _selectedContentTab = _DetailsContentTab.episodes;

  MediaItem get item => widget.item;
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    if (item.type == MediaType.series) {
      _seriesFuture = state.loadSeriesDetails(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final progress = state.progressFor(item);
        final size = MediaQuery.sizeOf(context);
        final compact = size.width < 720;
        final related = _recommendedItems();

        return Scaffold(
          backgroundColor: Colors.black,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: state.isTelevision
                    ? 700
                    : (compact ? 430 : 590),
                pinned: true,
                stretch: true,
                backgroundColor: Colors.black,
                surfaceTintColor: Colors.transparent,
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetworkArt(url: item.backdropUrl, fit: BoxFit.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x33000000),
                              Color(0x11000000),
                              Color(0xDD000000),
                              Colors.black,
                            ],
                            stops: [0, 0.36, 0.78, 1],
                          ),
                        ),
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [Color(0xE6000000), Color(0x66000000), Color(0x05000000)],
                            stops: [0, 0.46, 1],
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              compact ? 22 : 56,
                              0,
                              compact ? 22 : 56,
                              compact ? 32 : 54,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: compact ? size.width : 650,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      if (item.isNew) const _PremiumBadge(label: 'Recién añadido'),
                                      _PremiumBadge(label: item.typeLabel),
                                      if (!item.isLive && item.year > 0)
                                        _PremiumBadge(label: '${item.year}'),
                                      if (item.rating > 0)
                                        _PremiumBadge(label: '★ ${item.rating.toStringAsFixed(1)}'),
                                      if (item.durationLabel.trim().isNotEmpty)
                                        _PremiumBadge(label: item.durationLabel),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    item.title,
                                    maxLines: compact ? 3 : 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                                          fontSize: state.isTelevision
                                              ? 64
                                              : (compact ? 40 : 58),
                                          height: 0.98,
                                          shadows: const [
                                            Shadow(
                                              color: Colors.black87,
                                              blurRadius: 24,
                                            ),
                                          ],
                                        ),
                                  ),
                                  const SizedBox(height: 14),
                                  Text(
                                    item.description,
                                    maxLines: compact ? 3 : 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.82),
                                      fontSize: compact ? 14.5 : 17,
                                      height: 1.45,
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  _PrimaryActionBar(
                                    item: item,
                                    state: state,
                                    progress: progress,
                                    label: _mainButtonLabel(progress),
                                    onPlay: _mainPlayAction,
                                    onFavorite: () => state.toggleFavorite(item),
                                    downloadButton: item.type == MediaType.movie
                                        ? _buildMovieDownloadButton()
                                        : null,
                                    onTrailer: (item.type == MediaType.movie ||
                                            item.trailerUrl.trim().isNotEmpty)
                                        ? _openTrailer
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1220),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (progress > 0 && !item.isLive) ...[
                            _ProgressPanel(progress: progress),
                            const SizedBox(height: 24),
                          ],
                          if (item.genres.isNotEmpty || item.cast.isNotEmpty)
                            _InfoPanel(item: item),
                          if (item.type == MediaType.series) ...[
                            const SizedBox(height: 30),
                            _PremiumTabs(
                              first: 'Episodios',
                              second: related.isEmpty ? null : 'Quizá también te guste',
                              selected: _selectedContentTab,
                              onFirst: () => setState(
                                () => _selectedContentTab = _DetailsContentTab.episodes,
                              ),
                              onSecond: related.isEmpty
                                  ? null
                                  : () => setState(
                                        () => _selectedContentTab =
                                            _DetailsContentTab.recommendations,
                                      ),
                            ),
                            const SizedBox(height: 20),
                            if (_selectedContentTab ==
                                _DetailsContentTab.recommendations)
                              _buildRecommendationsSection(related)
                            else
                              _buildSeriesSection(),
                          ] else if (related.isNotEmpty) ...[
                            const SizedBox(height: 30),
                            _buildRecommendationsSection(related),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          ),
        );
      },
    );
  }

  List<MediaItem> _recommendedItems() {
    final selectedGenres = item.genres
        .map((genre) => genre.trim().toLowerCase())
        .where((genre) => genre.isNotEmpty)
        .toSet();
    final selectedKeywords = item.keywords
        .map((keyword) => keyword.trim().toLowerCase())
        .where((keyword) => keyword.isNotEmpty)
        .toSet();
    final selectedFranchise = item.franchise?.trim().toLowerCase();

    final scored = <_RecommendationMatch>[];
    for (final candidate in state.catalog) {
      if (candidate.id == item.id || candidate.isLive) continue;

      var score = 0;
      if (candidate.type == item.type) score += 8;
      if (candidate.franchise != null &&
          selectedFranchise != null &&
          candidate.franchise!.trim().toLowerCase() == selectedFranchise) {
        score += 28;
      }

      final candidateGenres = candidate.genres
          .map((genre) => genre.trim().toLowerCase())
          .where((genre) => genre.isNotEmpty)
          .toSet();
      final sharedGenres = candidateGenres.intersection(selectedGenres).length;
      score += sharedGenres * 10;

      final candidateKeywords = candidate.keywords
          .map((keyword) => keyword.trim().toLowerCase())
          .where((keyword) => keyword.isNotEmpty)
          .toSet();
      final sharedKeywords = candidateKeywords.intersection(selectedKeywords).length;
      score += sharedKeywords * 4;

      if (candidate.year > 0 && item.year > 0) {
        final distance = (candidate.year - item.year).abs();
        if (distance <= 2) {
          score += 4;
        } else if (distance <= 5) {
          score += 2;
        }
      }
      if (candidate.rating >= item.rating && candidate.rating > 0) score += 2;
      if (candidate.isNew) score += 1;

      if (score > 0) {
        scored.add(_RecommendationMatch(candidate, score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      final ratingCompare = b.item.rating.compareTo(a.item.rating);
      if (ratingCompare != 0) return ratingCompare;
      return b.item.addedAt.compareTo(a.item.addedAt);
    });

    final recommended = <MediaItem>[];
    final used = <String>{};
    for (final match in scored) {
      if (used.add(match.item.id)) recommended.add(match.item);
      if (recommended.length >= 24) return recommended;
    }

    final fallback = state.catalog.where((candidate) {
      return candidate.id != item.id &&
          !candidate.isLive &&
          candidate.type == item.type &&
          used.add(candidate.id);
    }).toList()
      ..sort((a, b) {
        final newCompare = (b.isNew ? 1 : 0).compareTo(a.isNew ? 1 : 0);
        if (newCompare != 0) return newCompare;
        final ratingCompare = b.rating.compareTo(a.rating);
        if (ratingCompare != 0) return ratingCompare;
        return b.addedAt.compareTo(a.addedAt);
      });

    for (final candidate in fallback) {
      recommended.add(candidate);
      if (recommended.length >= 24) break;
    }

    return recommended;
  }

  Widget _buildRecommendationsSection(List<MediaItem> related) {
    if (related.isEmpty) {
      return const _SectionMessage(
        icon: Icons.auto_awesome_rounded,
        title: 'Aún no hay recomendaciones para este título',
      );
    }

    return MediaRow(
      title: 'Quizá también te guste',
      subtitle: 'Contenido parecido seleccionado automáticamente.',
      items: related,
      state: state,
      onItemTap: (candidate) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DetailsScreen(
              item: candidate,
              state: state,
            ),
          ),
        );
      },
    );
  }

  String _mainButtonLabel(double progress) {
    if (item.isLive) return 'Ver canal en vivo';
    if (item.type == MediaType.series) {
      return progress > 0 ? 'Continuar serie' : 'Ver primer episodio';
    }
    if (progress > 0 && progress < 0.95) {
      return 'Continuar ${(progress * 100).round()}%';
    }
    return progress >= 0.95 ? 'Volver a ver' : 'Reproducir';
  }

  Future<void> _mainPlayAction() async {
    if (item.type == MediaType.series) {
      SeriesDetails? details = _loadedSeries;
      try {
        final future = _seriesFuture;
        if (details == null && future != null) details = await future;
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No fue posible cargar los episodios de esta serie.'),
          ),
        );
        return;
      }
      if (details == null || details.allEpisodes.isEmpty) return;
      final episode = state.resumeEpisodeFor(item, details);
      await _openEpisode(episode, details: details);
      return;
    }

    var initialProgress = state.progressFor(item);
    if (initialProgress >= 0.95) {
      await state.restart(item);
      initialProgress = 0;
    } else if (initialProgress >= 0.01) {
      final choice = await _chooseResumeAction(
        title: item.title,
        progress: initialProgress,
      );
      if (choice == null || !mounted) return;
      if (choice == _ResumeChoice.fromStart) {
        await state.restart(item);
        initialProgress = 0;
      }
    }

    final offline = item.type == MediaType.movie
        ? state.downloadForMovie(item)
        : null;
    if (!item.isPlayable && offline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El proveedor no entregó un enlace reproducible.'),
        ),
      );
      return;
    }

    final urls = [
      if (offline != null) offline.localPath,
      ...item.streamUrls,
    ];
    if (item.isLive) await state.markLiveChannelOpened(item);
    final opened = await PlatformService.openPlayer(
      PlayerLaunchPayload(
        title: item.title,
        urls: urls,
        isLive: item.isLive,
        initialProgress: initialProgress,
        previewImageUrl: item.backdropUrl,
        mediaItem: item,
      ).toJson(),
    );
    if (opened || !mounted) return;

    final upNext = item.type == MediaType.movie ? state.upNextFor(item) : null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          appState: state,
          title: item.title,
          urls: urls,
          isLive: item.isLive,
          initialProgress: initialProgress,
          previewImageUrl: item.backdropUrl,
          onProgress: item.isLive
              ? null
              : (value) => state.savePlaybackProgress(item, value),
          upNextTitle: upNext?.title,
          onPlayUpNext: upNext == null
              ? null
              : () => _openUpNextFromPlayer(upNext),
        ),
      ),
    );
  }

  Future<void> _openUpNextFromPlayer(MediaItem next) async {
    final navigator = Navigator.of(context);
    navigator.pop();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => DetailsScreen(item: next, state: state),
      ),
    );
  }

  Widget _buildMovieDownloadButton() {
    final id = 'movie-${item.id}';
    final downloaded = state.downloadForMovie(item) != null;
    final downloading = state.isDownloading(id);
    final progress = state.downloadProgress(id);

    if (downloading) {
      return OutlinedButton.icon(
        onPressed: () => state.cancelDownload(id),
        icon: SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            value: progress > 0 ? progress : null,
          ),
        ),
        label: Text(
          progress > 0
              ? 'Descargando ${(progress * 100).round()}%'
              : 'Preparando descarga',
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: downloaded ? null : _downloadMovie,
      icon: Icon(
        downloaded ? Icons.download_done_rounded : Icons.download_rounded,
      ),
      label: Text(downloaded ? 'Descargada' : 'Descargar'),
    );
  }

  Future<void> _downloadMovie() async {
    final error = await state.downloadMovie(item);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _downloadEpisode(EpisodeItem episode) async {
    final error = await state.downloadEpisode(item, episode);
    if (!mounted || error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  Future<void> _openTrailer() async {
    final trailer = await state.loadTrailer(item);
    final uri = Uri.tryParse(trailer);
    final opened = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este título no incluye un tráiler disponible.'),
        ),
      );
    }
  }

  Widget _buildSeriesSection() {
    final future = _seriesFuture;
    if (future == null) return const SizedBox.shrink();

    return FutureBuilder<SeriesDetails>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SectionMessage(
            icon: Icons.downloading_rounded,
            title: 'Cargando temporadas y episodios…',
            loading: true,
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _SectionMessage(
            icon: Icons.error_outline_rounded,
            title: 'No pudimos cargar los episodios',
            subtitle: '${snapshot.error ?? 'Respuesta no compatible.'}',
            actionLabel: 'Reintentar',
            onAction: () {
              setState(() {
                _loadedSeries = null;
                _selectedSeason = null;
                _seriesFuture = state.loadSeriesDetails(item);
              });
            },
          );
        }

        final details = snapshot.data!;
        _loadedSeries = details;
        final numbers = details.seasonNumbers;
        if (numbers.isEmpty) {
          return const _SectionMessage(
            icon: Icons.video_library_outlined,
            title: 'No hay episodios disponibles',
          );
        }
        final selected = _selectedSeason != null &&
                numbers.contains(_selectedSeason)
            ? _selectedSeason!
            : numbers.first;
        final episodes = details.seasons[selected] ?? const [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      value: selected,
                      dropdownColor: const Color(0xFF171A20),
                      borderRadius: BorderRadius.circular(14),
                      items: numbers
                          .map(
                            (number) => DropdownMenuItem<int>(
                              value: number,
                              child: Text('Temporada $number'),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedSeason = value);
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: (episodes.length * 148.0).clamp(240.0, 760.0).toDouble(),
              child: ListView.separated(
                key: PageStorageKey<String>('season-$selected'),
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: episodes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  final download = state.downloadForEpisode(episode);
                  final downloadId = 'episode-${episode.id}';
                  return _EpisodeTile(
                    episode: episode,
                    progress: state.episodeProgress(episode.id),
                    fallbackImage: item.backdropUrl,
                    onTap: () => _openEpisode(episode),
                    downloaded: download != null,
                    downloading: state.isDownloading(downloadId),
                    downloadProgress: state.downloadProgress(downloadId),
                    onDownload: () => _downloadEpisode(episode),
                    onCancelDownload: () => state.cancelDownload(downloadId),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openEpisode(
    EpisodeItem episode, {
    SeriesDetails? details,
  }) async {
    SeriesDetails? loaded = details ?? _loadedSeries;
    final future = _seriesFuture;
    if (loaded == null && future != null) {
      try {
        loaded = await future;
      } catch (_) {
        loaded = null;
      }
    }
    if (!mounted) return;
    if (loaded == null || loaded.allEpisodes.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fue posible preparar esta temporada.')),
      );
      return;
    }
    final seriesDetails = loaded;
    var initialEpisodeProgress = state.episodeProgress(episode.id);
    if (initialEpisodeProgress >= 0.95) {
      await state.restartEpisode(item, episode);
      initialEpisodeProgress = 0;
    } else if (initialEpisodeProgress >= 0.01) {
      final choice = await _chooseResumeAction(
        title: '${episode.numberLabel} • ${episode.title}',
        progress: initialEpisodeProgress,
      );
      if (choice == null || !mounted) return;
      if (choice == _ResumeChoice.fromStart) {
        await state.restartEpisode(item, episode);
        initialEpisodeProgress = 0;
      }
    }

    final offline = state.downloadForEpisode(episode);
    if (episode.streamUrls.isEmpty && offline == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este episodio no tiene enlace de video.')),
      );
      return;
    }

    final playerEpisodes = seriesDetails.allEpisodes.map((candidate) {
      final candidateOffline = state.downloadForEpisode(candidate);
      return PlayerEpisode(
        episode: candidate,
        urls: [
          if (candidateOffline != null) candidateOffline.localPath,
          ...candidate.streamUrls,
        ],
        initialProgress: candidate.id == episode.id
            ? initialEpisodeProgress
            : state.episodeProgress(candidate.id),
        previewImageUrl: candidate.imageUrl.isNotEmpty
            ? candidate.imageUrl
            : item.backdropUrl,
      );
    }).toList(growable: false);

    await state.markEpisodeStarted(item, episode);
    if (!mounted) return;
    final urls = [
      if (offline != null) offline.localPath,
      ...episode.streamUrls,
    ];
    final opened = await PlatformService.openPlayer(
      PlayerLaunchPayload(
        title: item.title,
        subtitle: '${episode.numberLabel} • ${episode.title}',
        urls: urls,
        isLive: false,
        initialProgress: initialEpisodeProgress,
        previewImageUrl: episode.imageUrl.isNotEmpty
            ? episode.imageUrl
            : item.backdropUrl,
        mediaItem: item,
        episodes: playerEpisodes
            .map(
              (entry) => PlayerEpisodePayload(
                episode: entry.episode,
                urls: entry.urls,
                initialProgress: entry.initialProgress,
                previewImageUrl: entry.previewImageUrl,
              ),
            )
            .toList(growable: false),
        initialEpisodeId: episode.id,
      ).toJson(),
    );
    if (opened || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VideoPlayerScreen(
          appState: state,
          title: item.title,
          subtitle: '${episode.numberLabel} • ${episode.title}',
          urls: urls,
          isLive: false,
          initialProgress: initialEpisodeProgress,
          previewImageUrl: episode.imageUrl.isNotEmpty
              ? episode.imageUrl
              : item.backdropUrl,
          episodes: playerEpisodes,
          initialEpisodeId: episode.id,
          onEpisodeStarted: (episodeId) async {
            final selected = seriesDetails.findEpisode(episodeId);
            if (selected != null) {
              await state.markEpisodeStarted(item, selected);
            }
          },
          onEpisodeProgress: (episodeId, value) async {
            final selected = seriesDetails.findEpisode(episodeId);
            if (selected != null) {
              await state.saveSeriesEpisodeProgress(
                item,
                seriesDetails,
                selected,
                value,
              );
            }
          },
        ),
      ),
    );
  }

  Future<_ResumeChoice?> _chooseResumeAction({
    required String title,
    required double progress,
  }) {
    return showModalBottomSheet<_ResumeChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Tienes ${(progress * 100).round()}% visto. Elige cómo reproducir.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.68),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _ResumeChoice.continueWatching,
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Continuar donde me quedé'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(
                  context,
                  _ResumeChoice.fromStart,
                ),
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Ver desde el inicio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _ResumeChoice { continueWatching, fromStart }

enum _DetailsContentTab { episodes, recommendations }

class _RecommendationMatch {
  const _RecommendationMatch(this.item, this.score);

  final MediaItem item;
  final int score;
}

class _EpisodeTile extends StatefulWidget {
  const _EpisodeTile({
    required this.episode,
    required this.progress,
    required this.fallbackImage,
    required this.onTap,
    required this.downloaded,
    required this.downloading,
    required this.downloadProgress,
    required this.onDownload,
    required this.onCancelDownload,
  });

  final EpisodeItem episode;
  final double progress;
  final String fallbackImage;
  final VoidCallback onTap;
  final bool downloaded;
  final bool downloading;
  final double downloadProgress;
  final VoidCallback onDownload;
  final VoidCallback onCancelDownload;

  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: _focused
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _focused
              ? Colors.white.withValues(alpha: 0.32)
              : Colors.white.withValues(alpha: 0.07),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          onFocusChange: (value) => setState(() => _focused = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 650;
                final imageWidth = compact ? 132.0 : 250.0;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: imageWidth,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            NetworkArt(
                              url: widget.episode.imageUrl.isEmpty
                                  ? widget.fallbackImage
                                  : widget.episode.imageUrl,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            const Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.play_arrow_rounded, size: 24),
                              ),
                            ),
                            if (widget.progress > 0)
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(9),
                                  ),
                                  child: LinearProgressIndicator(
                                    value: widget.progress,
                                    minHeight: 4,
                                    backgroundColor: Colors.black54,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${widget.episode.episodeNumber}. ${widget.episode.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.episode.durationLabel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.66),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.episode.description,
                            maxLines: compact ? 2 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.74),
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.downloading)
                      IconButton(
                        tooltip: 'Cancelar descarga',
                        onPressed: widget.onCancelDownload,
                        icon: SizedBox.square(
                          dimension: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            value: widget.downloadProgress > 0
                                ? widget.downloadProgress
                                : null,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        tooltip: widget.downloaded
                            ? 'Descargado'
                            : 'Descargar episodio',
                        onPressed: widget.downloaded ? null : widget.onDownload,
                        icon: Icon(
                          widget.downloaded
                              ? Icons.download_done_rounded
                              : Icons.download_rounded,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Más opciones',
                      onPressed: widget.onTap,
                      icon: const Icon(Icons.more_vert_rounded),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.36),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _PrimaryActionBar extends StatelessWidget {
  const _PrimaryActionBar({
    required this.item,
    required this.state,
    required this.progress,
    required this.label,
    required this.onPlay,
    required this.onFavorite,
    this.downloadButton,
    this.onTrailer,
  });

  final MediaItem item;
  final AppState state;
  final double progress;
  final String label;
  final VoidCallback onPlay;
  final VoidCallback onFavorite;
  final Widget? downloadButton;
  final VoidCallback? onTrailer;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ElevatedButton.icon(
          autofocus: state.isTelevision,
          onPressed: onPlay,
          icon: Icon(item.isLive ? Icons.live_tv_rounded : Icons.play_arrow_rounded),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(170, 54),
            textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ),
        if (downloadButton != null) downloadButton!,
        _HeroIconButton(
          icon: state.isFavorite(item) ? Icons.check_rounded : Icons.add_rounded,
          label: state.isFavorite(item) ? 'En Mi lista' : 'Mi lista',
          onTap: onFavorite,
        ),
        if (onTrailer != null)
          _HeroIconButton(
            icon: Icons.movie_filter_outlined,
            label: 'Tráiler',
            onTap: onTrailer!,
          ),
      ],
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.10),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 54),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
      ),
    );
  }
}

class _ProgressPanel extends StatelessWidget {
  const _ProgressPanel({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.play_circle_outline_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(progress * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.075)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.genres.isNotEmpty)
              Text(
                item.genres.join(' • '),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            if (item.cast.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Reparto: ${item.cast.take(8).join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.64)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PremiumTabs extends StatelessWidget {
  const _PremiumTabs({
    required this.first,
    required this.selected,
    required this.onFirst,
    this.second,
    this.onSecond,
  });

  final String first;
  final String? second;
  final _DetailsContentTab selected;
  final VoidCallback onFirst;
  final VoidCallback? onSecond;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          _PremiumTabLabel(
            label: first,
            selected: selected == _DetailsContentTab.episodes,
            onTap: onFirst,
          ),
          if (second != null)
            _PremiumTabLabel(
              label: second!,
              selected: selected == _DetailsContentTab.recommendations,
              onTap: onSecond,
            ),
        ],
      ),
    );
  }
}

class _PremiumTabLabel extends StatelessWidget {
  const _PremiumTabLabel({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 26),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.48),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: selected ? 86 : 0,
                height: 3,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionMessage extends StatelessWidget {
  const _SectionMessage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            if (loading)
              const SizedBox.square(
                dimension: 30,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(icon, size: 34),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onAction != null && actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
