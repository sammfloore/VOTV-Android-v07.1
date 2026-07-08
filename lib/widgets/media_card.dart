import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import 'network_art.dart';

enum ContinueWatchingAction { info, restart, remove }

class MediaCard extends StatefulWidget {
  const MediaCard({
    super.key,
    required this.item,
    required this.state,
    required this.onTap,
    this.width = 158,
    this.showProgress = false,
    this.liveLayout = false,
    this.showContinueMenu = false,
    this.onContinueAction,
    this.autofocus = false,
  });

  final MediaItem item;
  final AppState state;
  final VoidCallback onTap;
  final double width;
  final bool showProgress;
  final bool liveLayout;
  final bool showContinueMenu;
  final ValueChanged<ContinueWatchingAction>? onContinueAction;
  final bool autofocus;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final state = widget.state;
    final progress = state.progressFor(item);
    final resolvedWidth =
        widget.width.isFinite && widget.width > 0 ? widget.width : 180.0;
    final imageCacheWidth = widget.liveLayout
        ? (resolvedWidth * 2).round().clamp(220, 720).toInt()
        : (resolvedWidth * 2.4).round().clamp(260, 840).toInt();
    final tv = state.isTelevision;

    return RepaintBoundary(
      child: AnimatedScale(
        scale: _focused && tv ? 1.075 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: _focused && tv
                ? [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.34),
                      blurRadius: 26,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: Semantics(
            button: true,
            label: '${item.title}, ${item.typeLabel}',
            child: InkWell(
              autofocus: widget.autofocus,
              focusColor: Colors.transparent,
              hoverColor: Colors.white.withValues(alpha: 0.04),
              splashColor: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
              onFocusChange: (focused) {
                if (_focused != focused) setState(() => _focused = focused);
                if (focused && tv) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    Scrollable.ensureVisible(
                      context,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      alignment: 0.16,
                    );
                  });
                }
              },
              onTap: widget.onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: widget.liveLayout ? 16 / 9 : 2 / 3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetworkArt(
                          url: item.posterUrl,
                          fit: widget.liveLayout ? BoxFit.contain : BoxFit.cover,
                          borderRadius: BorderRadius.circular(16),
                          cacheWidth: imageCacheWidth,
                          fallbackLabel: item.title,
                          live: item.isLive,
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: widget.liveLayout
                                  ? const [
                                      Color(0x11000000),
                                      Color(0x99000000),
                                    ]
                                  : const [
                                      Colors.transparent,
                                      Color(0xB3000000),
                                    ],
                              stops: const [0.52, 1],
                            ),
                            border: Border.all(
                              color: _focused && tv
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.white.withValues(alpha: 0.10),
                              width: _focused && tv ? 3 : 1,
                            ),
                          ),
                        ),
                        if (item.isLive)
                          const Positioned(
                            left: 9,
                            top: 9,
                            child: _Badge(
                              text: 'EN VIVO',
                              color: Colors.redAccent,
                            ),
                          )
                        else if (progress >= 0.95)
                          const Positioned(
                            left: 9,
                            top: 9,
                            child: _Badge(
                              text: 'VISTO',
                              color: Color(0xFFB9C5D2),
                            ),
                          )
                        else if (item.isNew)
                          Positioned(
                            left: 9,
                            top: 9,
                            child: _Badge(
                              text: 'NUEVO',
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        if (!widget.liveLayout)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: widget.showContinueMenu
                                ? _ContinueMenu(
                                    onSelected: widget.onContinueAction,
                                  )
                                : _FavoriteButton(item: item, state: state),
                          ),
                        if (!widget.liveLayout && item.rating > 0)
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 10,
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 16,
                                  color: Color(0xFFFFD166),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  item.rating.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (widget.showProgress && progress > 0) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: tv ? 6 : 4,
                        backgroundColor:
                            Colors.white.withValues(alpha: 0.12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 9),
                  Text(
                    item.title,
                    maxLines: widget.liveLayout ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: tv ? 17 : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.isLive
                        ? (item.genres.isEmpty
                            ? 'Canal en vivo'
                            : item.genres.first)
                        : '${item.year}  •  ${item.typeLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: tv ? 14 : 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ContinueMenu extends StatelessWidget {
  const _ContinueMenu({required this.onSelected});

  final ValueChanged<ContinueWatchingAction>? onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.68),
      shape: const CircleBorder(),
      child: PopupMenuButton<ContinueWatchingAction>(
        tooltip: 'Opciones de reproducción',
        icon: const Icon(Icons.more_vert_rounded, size: 21),
        onSelected: onSelected,
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: ContinueWatchingAction.info,
            child: ListTile(
              leading: Icon(Icons.info_outline_rounded),
              title: Text('Ver información'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: ContinueWatchingAction.restart,
            child: ListTile(
              leading: Icon(Icons.replay_rounded),
              title: Text('Ver desde el inicio'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          PopupMenuItem(
            value: ContinueWatchingAction.remove,
            child: ListTile(
              leading: Icon(Icons.remove_circle_outline_rounded),
              title: Text('Quitar de Continuar viendo'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.item, required this.state});

  final MediaItem item;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final selected = state.isFavorite(item);
        return Material(
          color: Colors.black.withValues(alpha: 0.62),
          shape: const CircleBorder(),
          child: IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: selected ? 'Quitar de Mi lista' : 'Agregar a Mi lista',
            onPressed: () => state.toggleFavorite(item),
            icon: Icon(
              selected ? Icons.check_rounded : Icons.add_rounded,
              size: 20,
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            fontSize: 9,
            letterSpacing: 0.7,
          ),
        ),
      ),
    );
  }
}
