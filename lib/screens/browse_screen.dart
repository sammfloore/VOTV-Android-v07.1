import 'dart:async';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../widgets/media_card.dart';
import 'details_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.state,
    required this.type,
  });

  final AppState state;
  final MediaType type;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;
  String _query = '';

  List<MediaItem> get _catalogItems => widget.type == MediaType.movie
      ? widget.state.movies
      : widget.state.series;

  String get _title =>
      widget.type == MediaType.movie ? 'Películas' : 'Series';

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _catalogItems;
    final search = widget.state.searchResult(
      _query,
      type: widget.type,
      limit: allItems.length,
    );
    final visibleItems = _query.trim().isEmpty ? allItems : search.items;

    return CustomScrollView(
      key: PageStorageKey<String>('browse-${widget.type.name}'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      cacheExtent: 520,
      slivers: [
        SliverAppBar.large(
          title: Text('$_title (${allItems.length})'),
          backgroundColor: const Color(0xFF080A0D),
          actions: [
            IconButton(
              tooltip: 'Buscar en $_title',
              onPressed: () => _searchFocus.requestFocus(),
              icon: const Icon(Icons.search_rounded),
            ),
            if (!widget.state.isDemo)
              IconButton(
                tooltip: 'Actualizar catálogo',
                onPressed: widget.state.isRefreshingCatalog
                    ? null
                    : () => _refresh(context),
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
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _CatalogSearchBox(
              controller: _searchController,
              focusNode: _searchFocus,
              title: _title,
              onChanged: _onSearchChanged,
              onSubmitted: (value) => setState(() => _query = value.trim()),
              onClear: _clearSearch,
            ),
          ),
        ),
        if (_query.trim().isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      visibleItems.isEmpty
                          ? 'No encontramos resultados para “${_query.trim()}”'
                          : '${visibleItems.length} resultado${visibleItems.length == 1 ? '' : 's'} en $_title',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (search.usedFuzzyMatching)
                    const _FuzzyBadge(),
                ],
              ),
            ),
          ),
        if (search.suggestion != null && _query.trim().isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _applySuggestion(search.suggestion!),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '¿Buscabas “${search.suggestion}”?',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (visibleItems.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyCatalog(
              title: _title,
              hasQuery: _query.trim().isNotEmpty,
              onClear: _query.trim().isEmpty ? null : _clearSearch,
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.crossAxisExtent;
                final count = width >= 1300
                    ? 7
                    : width >= 1000
                        ? 6
                        : width >= 760
                            ? 5
                            : width >= 520
                                ? 4
                                : 3;
                return SliverGrid.builder(
                  itemCount: visibleItems.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 20,
                    childAspectRatio: 0.58,
                  ),
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    return MediaCard(
                      key: ValueKey(item.id),
                      item: item,
                      state: widget.state,
                      width: double.infinity,
                      onTap: () => _open(context, item),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() => _query = '');
  }

  void _applySuggestion(String suggestion) {
    _searchController.text = suggestion;
    _searchController.selection = TextSelection.collapsed(
      offset: suggestion.length,
    );
    setState(() => _query = suggestion);
  }

  Future<void> _refresh(BuildContext context) async {
    setState(() {});
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

  void _open(BuildContext context, MediaItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DetailsScreen(item: item, state: widget.state),
      ),
    );
  }
}

class _CatalogSearchBox extends StatelessWidget {
  const _CatalogSearchBox({
    required this.controller,
    required this.focusNode,
    required this.title,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String title;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF15191F),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: focused
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.09),
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.13),
                      blurRadius: 20,
                    ),
                  ]
                : const [],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: 'Buscar $title aunque escribas diferente',
              prefixIcon: const Icon(Icons.manage_search_rounded, size: 27),
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpiar búsqueda',
                      onPressed: onClear,
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 18,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FuzzyBadge extends StatelessWidget {
  const _FuzzyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primary
            .withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.spellcheck_rounded, size: 16),
          SizedBox(width: 6),
          Text(
            'Búsqueda inteligente',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog({
    required this.title,
    required this.hasQuery,
    this.onClear,
  });

  final String title;
  final bool hasQuery;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasQuery
                  ? Icons.search_off_rounded
                  : Icons.inventory_2_outlined,
              size: 68,
              color: Colors.white.withValues(alpha: 0.34),
            ),
            const SizedBox(height: 16),
            Text(
              hasQuery
                  ? 'No encontramos coincidencias'
                  : 'No hay $title disponibles',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? 'Prueba con menos palabras. La búsqueda también tolera errores de escritura.'
                  : 'Actualiza el catálogo o revisa los permisos de la cuenta.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.58)),
            ),
            if (onClear != null) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Mostrar todo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
