import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import 'media_card.dart';

class MediaRow extends StatelessWidget {
  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    required this.state,
    required this.onItemTap,
    this.subtitle,
    this.showProgress = false,
    this.showContinueMenu = false,
  });

  final String title;
  final String? subtitle;
  final List<MediaItem> items;
  final AppState state;
  final ValueChanged<MediaItem> onItemTap;
  final bool showProgress;
  final bool showContinueMenu;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final width = MediaQuery.sizeOf(context).width;
    final tv = state.isTelevision;
    final cardWidth = tv
        ? (width >= 1500 ? 230.0 : 205.0)
        : width >= 1200
            ? 190.0
            : width >= 700
                ? 172.0
                : 148.0;

    return Padding(
      padding: EdgeInsets.only(bottom: tv ? 46 : 34),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tv ? 34 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: tv ? 25 : null,
                      ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 15),
          SizedBox(
            height: cardWidth * 1.5 + (showProgress ? 96 : 84),
            child: ListView.separated(
              clipBehavior: Clip.none,
              padding: EdgeInsets.fromLTRB(
                tv ? 34 : 20,
                tv ? 14 : 0,
                tv ? 34 : 20,
                tv ? 18 : 0,
              ),
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => SizedBox(width: tv ? 20 : 14),
              itemBuilder: (context, index) {
                final item = items[index];
                return MediaCard(
                  item: item,
                  state: state,
                  width: cardWidth,
                  showProgress: showProgress,
                  showContinueMenu: showContinueMenu,
                  onContinueAction: (action) async {
                    if (action == ContinueWatchingAction.info) {
                      onItemTap(item);
                      return;
                    }
                    if (action == ContinueWatchingAction.restart) {
                      await state.restart(item);
                      if (context.mounted) onItemTap(item);
                      return;
                    }
                    await state.removeFromContinueWatching(item);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${item.title} se quitó de Continuar viendo.',
                        ),
                      ),
                    );
                  },
                  onTap: () => onItemTap(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
