import 'dart:async';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../widgets/brand_logo.dart';
import 'browse_screen.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'live_screen.dart';
import 'search_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.state});

  final AppState state;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.state.refreshCatalogIfStale());
      unawaited(widget.state.refreshDownloads());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  static const _destinations = <_Destination>[
    _Destination('Inicio', Icons.home_outlined, Icons.home_rounded),
    _Destination('En vivo', Icons.live_tv_outlined, Icons.live_tv_rounded),
    _Destination('Películas', Icons.movie_outlined, Icons.movie_rounded),
    _Destination(
      'Series',
      Icons.video_library_outlined,
      Icons.video_library_rounded,
    ),
    _Destination('Buscar', Icons.search_outlined, Icons.search_rounded),
    _Destination(
      'Mi espacio',
      Icons.bookmarks_outlined,
      Icons.bookmarks_rounded,
    ),
  ];

  Widget _currentPage() {
    return switch (_index) {
      0 => HomeScreen(
          key: const PageStorageKey<String>('home'),
          state: widget.state,
          accountName: widget.state.accountName,
          isDemo: widget.state.isDemo,
        ),
      1 => LiveScreen(
          key: const PageStorageKey<String>('live'),
          state: widget.state,
        ),
      2 => BrowseScreen(
          key: const PageStorageKey<String>('movies'),
          state: widget.state,
          type: MediaType.movie,
        ),
      3 => BrowseScreen(
          key: const PageStorageKey<String>('series'),
          state: widget.state,
          type: MediaType.series,
        ),
      4 => SearchScreen(
          key: const PageStorageKey<String>('search'),
          state: widget.state,
        ),
      _ => LibraryScreen(
          key: const PageStorageKey<String>('library'),
          state: widget.state,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tv = widget.state.isTelevision;
        final useRail = tv || constraints.maxWidth >= 980;
        final useExtendedRail = constraints.maxWidth >= (tv ? 1100 : 1280);
        final page = KeyedSubtree(
          key: ValueKey<int>(_index),
          child: _currentPage(),
        );

        if (!tv && constraints.maxWidth >= 900) {
          return Scaffold(
            body: Column(
              children: [
                _PremiumTopNavigation(
                  selectedIndex: _index,
                  accountName: widget.state.accountName,
                  isDemo: widget.state.isDemo,
                  onLogout: _confirmLogout,
                  onSelected: (index) {
                    if (index != _index) setState(() => _index = index);
                  },
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: page,
                  ),
                ),
              ],
            ),
          );
        }

        if (useRail) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    extended: useExtendedRail,
                    selectedIndex: _index,
                    onDestinationSelected: (index) {
                      if (index != _index) setState(() => _index = index);
                    },
                    backgroundColor: const Color(0xFF0D1116),
                    labelType: useExtendedRail
                        ? NavigationRailLabelType.none
                        : (tv ? NavigationRailLabelType.all : null),
                    groupAlignment: -0.92,
                    leading: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 12, 10, 26),
                      child: _RailLogo(extended: useExtendedRail),
                    ),
                    trailing: Padding(
                      padding: const EdgeInsets.only(top: 18, bottom: 16),
                      child: useExtendedRail
                          ? TextButton.icon(
                              onPressed: _confirmLogout,
                              icon: const Icon(Icons.logout_rounded),
                              label: const Text('Cerrar sesión'),
                            )
                          : IconButton(
                              tooltip: 'Cerrar sesión',
                              onPressed: _confirmLogout,
                              icon: const Icon(Icons.logout_rounded),
                            ),
                    ),
                    destinations: _destinations
                        .map(
                          (destination) => NavigationRailDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: Text(destination.label),
                          ),
                        )
                        .toList(),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: Colors.white.withValues(alpha: 0.07),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: page,
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: page,
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: _index,
              labelBehavior:
                  NavigationDestinationLabelBehavior.onlyShowSelected,
              onDestinationSelected: (index) {
                if (index != _index) setState(() => _index = index);
              },
              destinations: _destinations
                  .map(
                    (destination) => NavigationDestination(
                      icon: Icon(destination.icon),
                      selectedIcon: Icon(destination.selectedIcon),
                      label: destination.label,
                    ),
                  )
                  .toList(),
            ),
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: AvoTvLogo(size: 50, nameSize: 21),
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout_rounded),
                    title: const Text('Cerrar sesión'),
                    onTap: _confirmLogout,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          'La aplicación dejará de entrar automáticamente. Tu lista e historial local permanecerán en este dispositivo.',
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
    if (confirmed == true) await widget.state.signOut();
  }
}

class _RailLogo extends StatelessWidget {
  const _RailLogo({required this.extended});

  final bool extended;

  @override
  Widget build(BuildContext context) {
    return AvoTvLogo(size: 44, showName: extended, nameSize: 20);
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _PremiumTopNavigation extends StatelessWidget {
  const _PremiumTopNavigation({
    required this.selectedIndex,
    required this.onSelected,
    required this.onLogout,
    required this.accountName,
    required this.isDemo,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final VoidCallback onLogout;
  final String accountName;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xE6050607),
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xAA000000),
              blurRadius: 26,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(30, 14, 24, 12),
          child: Row(
            children: [
              const AvoTvLogo(size: 38, nameSize: 18),
              const SizedBox(width: 34),
              for (var index = 0;
                  index < _MainShellState._destinations.length;
                  index++)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _TopNavButton(
                    label: _MainShellState._destinations[index].label,
                    selected: selectedIndex == index,
                    onTap: () => onSelected(index),
                  ),
                ),
              const Spacer(),
              Flexible(
                child: Text(
                  isDemo ? 'Modo demostración' : accountName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.64),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Cerrar sesión',
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopNavButton extends StatelessWidget {
  const _TopNavButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: selected ? Colors.white : Colors.white70,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 5),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 32 : 0,
            height: 3,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ],
      ),
    );
  }
}
