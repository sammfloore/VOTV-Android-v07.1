import 'dart:async';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../state/app_state.dart';
import '../widgets/media_card.dart';
import 'details_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  String _query = '';
  MediaType? _filter;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.state.searchResult(
      _query,
      type: _filter,
      limit: 360,
    );
    final results = result.items;

    return CustomScrollView(
      key: const PageStorageKey<String>('professional-search'),
      cacheExtent: 420,
      slivers: [
        const SliverAppBar.large(
          title: Text('Buscar en AVO TV'),
          backgroundColor: Color(0xFF080A0D),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF15191F),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _focusNode.hasFocus
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white.withValues(alpha: 0.08),
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x44000000), blurRadius: 18),
                ],
              ),
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                autofocus: false,
                textInputAction: TextInputAction.search,
                onTap: () => setState(() {}),
                onSubmitted: (value) => setState(() => _query = value),
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 320), () {
                    if (mounted) setState(() => _query = value);
                  });
                },
                decoration: InputDecoration(
                  hintText:
                      'Película, serie, canal, actor o género; también acepta errores',
                  prefixIcon: const Icon(Icons.manage_search_rounded, size: 28),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar',
                          onPressed: () {
                            _debounce?.cancel();
                            _controller.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 19,
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                _filterChip('Todo', null),
                _filterChip('Películas', MediaType.movie),
                _filterChip('Series', MediaType.series),
                _filterChip('En vivo', MediaType.live),
              ],
            ),
          ),
        ),
        if (result.suggestion != null && _query.trim().isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Material(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    final suggestion = result.suggestion!;
                    _controller.text = suggestion;
                    _controller.selection = TextSelection.collapsed(
                      offset: suggestion.length,
                    );
                    setState(() => _query = suggestion);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome_rounded),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '¿Buscabas “${result.suggestion}”?',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Icon(Icons.arrow_forward_rounded),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _query.trim().isEmpty
                        ? 'Sugerencias para ti'
                        : '${results.length} resultados',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (result.usedFuzzyMatching && _query.trim().isNotEmpty)
                  Tooltip(
                    message:
                        'Se incluyeron coincidencias aproximadas para corregir errores de escritura.',
                    child: const Chip(
                      avatar: Icon(Icons.spellcheck_rounded, size: 18),
                      label: Text('Búsqueda inteligente'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (results.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.search_off_rounded,
                      size: 64,
                      color: Colors.white.withValues(alpha: 0.36),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'No encontramos coincidencias',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Prueba con otro título, actor, país, género o una palabra más corta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.58),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
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
                  itemCount: results.length,
                  addAutomaticKeepAlives: false,
                  addRepaintBoundaries: true,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 20,
                    childAspectRatio: 0.58,
                  ),
                  itemBuilder: (context, index) {
                    final item = results[index];
                    return MediaCard(
                      key: ValueKey(item.id),
                      item: item,
                      state: widget.state,
                      width: double.infinity,
                      showProgress: widget.state.progressFor(item) > 0,
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

  Widget _filterChip(String label, MediaType? type) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: _filter == type,
        label: Text(label),
        onSelected: (_) => setState(() => _filter = type),
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
