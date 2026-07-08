import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../widgets/media_row.dart';
import '../widgets/network_art.dart';
import '../widgets/brand_logo.dart';
import 'details_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.state,
    required this.accountName,
    required this.isDemo,
  });

  final AppState state;
  final String accountName;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        if (state.catalog.isEmpty) {
          return _EmptyHome(accountName: accountName);
        }

        final recommendations = state.recommendations;
        MediaItem? firstNonLive;
        for (final candidate in state.catalog) {
          if (!candidate.isLive) {
            firstNonLive = candidate;
            break;
          }
        }
        final hero = recommendations.isNotEmpty
            ? recommendations.first
            : firstNonLive ?? state.catalog.first;
        final popularMovies = state.movies.toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));
        final popularSeries = state.series.toList()
          ..sort((a, b) => b.rating.compareTo(a.rating));
        final genreGroups = <String, List<MediaItem>>{};
        for (final item in state.catalog.where((item) => !item.isLive)) {
          for (final genre in item.genres.take(3)) {
            final name = genre.trim();
            if (name.isEmpty) continue;
            genreGroups.putIfAbsent(name, () => <MediaItem>[]).add(item);
          }
        }
        final featuredGenres = genreGroups.entries
            .where((entry) => entry.value.length >= 4)
            .toList()
          ..sort((a, b) => b.value.length.compareTo(a.value.length));

        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: _HeroBanner(
                item: hero,
                state: state,
                accountName: accountName,
                isDemo: isDemo,
                onOpen: () => _open(context, hero),
              ),
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
            if (state.liveChannels.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: 'Ahora en vivo',
                  subtitle: 'Canales disponibles en tu cuenta.',
                  items: state.liveChannels.take(24).toList(),
                  state: state,
                  onItemTap: (item) => _open(context, item),
                ),
              ),
            if (state.continueWatching.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: 'Continuar viendo',
                  subtitle: 'Retoma donde te quedaste.',
                  items: state.continueWatching,
                  state: state,
                  showProgress: true,
                  showContinueMenu: true,
                  onItemTap: (item) => _open(context, item),
                ),
              ),
            if (state.myList.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: 'Mi lista',
                  subtitle: 'Tus películas y series guardadas.',
                  items: state.myList.take(30).toList(),
                  state: state,
                  onItemTap: (item) => _open(context, item),
                ),
              ),
            if (recommendations.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: 'Recomendado para ti',
                  subtitle: state.history.isEmpty
                      ? 'Lo mejor valorado para comenzar.'
                      : 'Basado en géneros, reparto y sagas que has visto.',
                  items: recommendations,
                  state: state,
                  onItemTap: (item) => _open(context, item),
                ),
              ),
            if (state.recentlyAdded.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: 'Catálogo nuevo',
                  items: state.recentlyAdded,
                  state: state,
                  onItemTap: (item) => _open(context, item),
                ),
              ),
            if (state.movies.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: 'Películas populares',
                  subtitle: 'Las mejor valoradas de tu catálogo.',
                  items: popularMovies.take(24).toList(),
                  state: state,
                  onItemTap: (item) => _open(context, item),
                ),
              ),
            if (state.series.isNotEmpty)
              SliverToBoxAdapter(
                child: MediaRow(
                  title: 'Series populares',
                  subtitle: 'Historias para seguir episodio tras episodio.',
                  items: popularSeries.take(24).toList(),
                  state: state,
                  onItemTap: (item) => _open(context, item),
                ),
              ),
            ...featuredGenres.take(4).map(
              (entry) => SliverToBoxAdapter(
                child: MediaRow(
                  title: entry.key,
                  items: entry.value.take(24).toList(),
                  state: state,
                  onItemTap: (item) => _open(context, item),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 30)),
          ],
        );
      },
    );
  }

  void _open(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailsScreen(item: item, state: state),
      ),
    );
  }
}

class _EmptyHome extends StatelessWidget {
  const _EmptyHome({required this.accountName});

  final String accountName;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: Text('Hola, $accountName'),
          backgroundColor: const Color(0xFF080A0D),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 72,
                    color: Colors.white.withValues(alpha: 0.34),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'La cuenta no entregó contenido',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Revisa que la cuenta tenga permisos para películas, series o canales en vivo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.item,
    required this.state,
    required this.accountName,
    required this.isDemo,
    required this.onOpen,
  });

  final MediaItem item;
  final AppState state;
  final String accountName;
  final bool isDemo;
  final VoidCallback onOpen;

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

  @override
  Widget build(BuildContext context) {
    final tv = state.isTelevision;
    final compact = !tv && MediaQuery.sizeOf(context).width < 700;
    return SizedBox(
      height: tv ? 720 : (compact ? 570 : 650),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetworkArt(url: item.backdropUrl, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x44000000), Color(0x33000000), Color(0xFF080A0D)],
                stops: [0, 0.48, 1],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [const Color(0xDD080A0D), Colors.transparent],
                stops: const [0, 0.78],
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                tv ? 54 : (compact ? 20 : 42),
                tv ? 28 : 20,
                tv ? 54 : (compact ? 20 : 42),
                tv ? 72 : (compact ? 38 : 58),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const AvoTvLogo(size: 42, nameSize: 19),
                      const Spacer(),
                      if (!isDemo)
                        IconButton(
                          tooltip: 'Actualizar catálogo',
                          onPressed: state.isRefreshingCatalog
                              ? null
                              : () => _refreshCatalog(context),
                          icon: state.isRefreshingCatalog
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Icon(Icons.sync_rounded),
                        ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          isDemo ? 'Modo demostración' : accountName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontSize: tv ? 68 : (compact ? 39 : 58),
                            height: 1.02,
                          ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Text(item.typeLabel),
                      if (!item.isLive) Text('${item.year}'),
                      if (item.rating > 0)
                        Text('★ ${item.rating.toStringAsFixed(1)}'),
                      if (item.genres.isNotEmpty) Text(item.genres.take(2).join(' • ')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CountPill(
                        icon: Icons.movie_outlined,
                        label: '${state.movies.length} películas',
                      ),
                      _CountPill(
                        icon: Icons.video_library_outlined,
                        label: '${state.series.length} series',
                      ),
                      _CountPill(
                        icon: Icons.live_tv_outlined,
                        label: '${state.liveChannels.length} canales',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 660),
                    child: Text(
                      item.description,
                      maxLines: compact ? 3 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                        fontSize: compact ? 14 : 17,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        autofocus: tv,
                        onPressed: onOpen,
                        icon: Icon(
                          item.isLive ? Icons.live_tv_rounded : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          item.isLive
                              ? 'Ver en vivo'
                              : (state.progressFor(item) > 0
                                  ? 'Continuar'
                                  : 'Ver ahora'),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: onOpen,
                        icon: const Icon(Icons.info_outline_rounded),
                        label: const Text('Más información'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => state.toggleFavorite(item),
                        icon: Icon(
                          state.isFavorite(item)
                              ? Icons.check_rounded
                              : Icons.add_rounded,
                        ),
                        label: const Text('Mi lista'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _CountPill extends StatelessWidget {
  const _CountPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
