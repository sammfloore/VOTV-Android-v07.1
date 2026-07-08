import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../widgets/media_row.dart';
import 'details_screen.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final continueWatching = state.continueWatching;
        final recent = state.recentlyWatched;
        final completedMovies = state.completedMovies;
        final seriesInProgress = state.seriesInProgress;

        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: const Text('Mi actividad'),
                backgroundColor: const Color(0xFF080A0D),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                  child: _ActivitySummary(
                    recentCount: recent.length,
                    continueCount: continueWatching.length,
                    completedCount: completedMovies.length,
                  ),
                ),
              ),
              if (!state.hasPlaybackActivity)
                const SliverToBoxAdapter(child: _EmptyActivity())
              else ...[
                if (continueWatching.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MediaRow(
                      title: 'Continuar viendo',
                      subtitle: 'Usa los tres puntos para quitar o reiniciar.',
                      items: continueWatching,
                      state: state,
                      showProgress: true,
                      showContinueMenu: true,
                      onItemTap: (item) => _open(context, item),
                    ),
                  ),
                if (seriesInProgress.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MediaRow(
                      title: 'Series en progreso',
                      items: seriesInProgress,
                      state: state,
                      showProgress: true,
                      showContinueMenu: true,
                      onItemTap: (item) => _open(context, item),
                    ),
                  ),
                if (completedMovies.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MediaRow(
                      title: 'Películas terminadas',
                      items: completedMovies,
                      state: state,
                      onItemTap: (item) => _open(context, item),
                    ),
                  ),
                if (recent.isNotEmpty)
                  SliverToBoxAdapter(
                    child: MediaRow(
                      title: 'Visto recientemente',
                      items: recent,
                      state: state,
                      onItemTap: (item) => _open(context, item),
                    ),
                  ),
              ],
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 36),
                  child: _HistoryManagement(state: state),
                ),
              ),
            ],
          ),
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

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({
    required this.recentCount,
    required this.continueCount,
    required this.completedCount,
  });

  final int recentCount;
  final int continueCount;
  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Expanded(child: _Count(value: continueCount, label: 'En progreso')),
            Expanded(child: _Count(value: recentCount, label: 'Recientes')),
            Expanded(child: _Count(value: completedCount, label: 'Terminadas')),
          ],
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 12, 30, 34),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 70,
            color: Colors.white.withValues(alpha: 0.32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Todavía no hay actividad',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            'Aquí aparecerán tus títulos recientes, avances y contenidos terminados.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
          ),
        ],
      ),
    );
  }
}

class _HistoryManagement extends StatelessWidget {
  const _HistoryManagement({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Historial y progreso',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Estas acciones no eliminan descargas ni favoritos.',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
        ),
        const SizedBox(height: 14),
        _ActionTile(
          icon: Icons.remove_red_eye_outlined,
          title: 'Borrar todo “Continuar viendo”',
          subtitle: 'Quita solamente los títulos que están en progreso.',
          onTap: () => _confirm(
            context,
            title: '¿Borrar Continuar viendo?',
            message:
                'Se restablecerán los títulos en progreso. Tu historial reciente, descargas y favoritos permanecerán.',
            actionLabel: 'Borrar',
            action: state.clearContinueWatching,
          ),
        ),
        _ActionTile(
          icon: Icons.movie_outlined,
          title: 'Restablecer progreso de películas',
          subtitle: 'Elimina el avance guardado únicamente de películas.',
          onTap: () => _confirm(
            context,
            title: '¿Restablecer películas?',
            message:
                'Se borrará el progreso y el historial de películas. Las descargas y favoritos no cambiarán.',
            actionLabel: 'Restablecer',
            action: state.resetMovieProgress,
          ),
        ),
        _ActionTile(
          icon: Icons.video_library_outlined,
          title: 'Restablecer progreso de series',
          subtitle: 'Elimina avances de series y episodios.',
          onTap: () => _confirm(
            context,
            title: '¿Restablecer series?',
            message:
                'Se borrará el progreso de series y episodios. Las descargas y favoritos no cambiarán.',
            actionLabel: 'Restablecer',
            action: state.resetSeriesProgress,
          ),
        ),
        _ActionTile(
          icon: Icons.delete_sweep_outlined,
          title: 'Borrar historial de reproducción',
          subtitle: 'Elimina todos los avances y títulos recientes.',
          destructive: true,
          onTap: () => _confirm(
            context,
            title: '¿Borrar todo el historial?',
            message:
                'Esta acción eliminará todos los avances guardados y la actividad reciente, pero no borrará descargas ni favoritos.',
            actionLabel: 'Borrar todo',
            action: state.clearPlaybackHistory,
          ),
        ),
      ],
    );
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('La actividad se actualizó correctamente.')),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Icon(
            icon,
            color: destructive ? Colors.redAccent : null,
          ),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }
}
