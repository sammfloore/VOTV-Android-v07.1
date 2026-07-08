import 'dart:collection';
import 'dart:math' as math;

import '../models/media_item.dart';

class CatalogSearchResult {
  const CatalogSearchResult({
    required this.items,
    this.usedFuzzyMatching = false,
    this.suggestion,
  });

  final List<MediaItem> items;
  final bool usedFuzzyMatching;
  final String? suggestion;
}

class CatalogSearchService {
  CatalogSearchService([List<MediaItem> items = const []]) {
    replaceCatalog(items);
  }

  List<_SearchDocument> _documents = const [];
  final LinkedHashMap<String, CatalogSearchResult> _cache = LinkedHashMap();

  void replaceCatalog(List<MediaItem> items) {
    _documents = List<_SearchDocument>.unmodifiable(
      items.map(_SearchDocument.new),
    );
    _cache.clear();
  }

  CatalogSearchResult search(
    String rawQuery, {
    MediaType? type,
    int limit = 280,
  }) {
    final normalizedQuery = normalizeSearchText(rawQuery);
    final cacheKey = '${type?.name ?? 'all'}|$limit|$normalizedQuery';
    final cached = _cache.remove(cacheKey);
    if (cached != null) {
      _cache[cacheKey] = cached;
      return cached;
    }

    if (normalizedQuery.isEmpty) {
      final items = _documents
          .where((document) => type == null || document.item.type == type)
          .map((document) => document.item)
          .take(limit)
          .toList(growable: false);
      return _remember(
        cacheKey,
        CatalogSearchResult(items: items),
      );
    }

    final terms = normalizedQuery
        .split(' ')
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
    final scored = <_ScoredDocument>[];
    var usedFuzzy = false;

    for (final document in _documents) {
      if (type != null && document.item.type != type) continue;
      final score = _score(document, normalizedQuery, terms);
      if (score == null) continue;
      if (score.usedFuzzy) usedFuzzy = true;
      scored.add(_ScoredDocument(document, score.value));
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      final ratingCompare = b.document.item.rating.compareTo(
        a.document.item.rating,
      );
      if (ratingCompare != 0) return ratingCompare;
      return a.document.item.title.compareTo(b.document.item.title);
    });

    final items = scored
        .take(limit)
        .map((entry) => entry.document.item)
        .toList(growable: false);
    String? suggestion;
    if (items.isNotEmpty && usedFuzzy) {
      final firstTitle = items.first.title;
      final normalizedTitle = normalizeSearchText(firstTitle);
      if (!normalizedTitle.contains(normalizedQuery) &&
          !normalizedQuery.contains(normalizedTitle)) {
        suggestion = firstTitle;
      }
    }

    return _remember(
      cacheKey,
      CatalogSearchResult(
        items: items,
        usedFuzzyMatching: usedFuzzy,
        suggestion: suggestion,
      ),
    );
  }

  CatalogSearchResult _remember(String key, CatalogSearchResult value) {
    _cache[key] = value;
    while (_cache.length > 28) {
      _cache.remove(_cache.keys.first);
    }
    return value;
  }

  _Score? _score(
    _SearchDocument document,
    String query,
    List<String> terms,
  ) {
    var score = 0.0;
    var fuzzy = false;

    if (document.title == query) {
      score += 1200;
    } else if (document.title.startsWith(query)) {
      score += 680;
    } else if (document.title.contains(query)) {
      score += 430;
    }

    for (final term in terms) {
      if (document.titleTokens.contains(term)) {
        score += 170;
        continue;
      }
      if (document.titleTokens.any((token) => token.startsWith(term))) {
        score += 125;
        continue;
      }
      if (document.compactText.contains(term)) {
        score += 72;
        continue;
      }

      final similarity = _bestTokenSimilarity(term, document.matchTokens);
      final threshold = switch (term.length) {
        <= 3 => 0.86,
        4 => 0.74,
        5 => 0.67,
        _ => 0.61,
      };
      if (similarity < threshold) return null;
      fuzzy = true;
      score += 44 + similarity * 76;
    }

    if (terms.length > 1 && document.title.contains(terms.join(' '))) {
      score += 180;
    }
    score += document.item.rating.clamp(0, 10).toDouble() * 1.8;
    if (document.item.isNew) score += 8;
    return _Score(score, fuzzy);
  }

  double _bestTokenSimilarity(String term, List<String> candidates) {
    var best = 0.0;
    for (final candidate in candidates) {
      if ((candidate.length - term.length).abs() > 3) continue;
      if (candidate.isNotEmpty && term.isNotEmpty) {
        final sameStart = candidate.codeUnitAt(0) == term.codeUnitAt(0);
        if (!sameStart && term.length <= 5) continue;
      }
      final distance = _boundedLevenshtein(term, candidate, 4);
      if (distance > 4) continue;
      final longest = math.max(term.length, candidate.length);
      if (longest == 0) return 1;
      final similarity = 1 - (distance / longest);
      if (similarity > best) best = similarity;
      if (best >= 0.92) break;
    }
    return best;
  }

  int _boundedLevenshtein(String left, String right, int maxDistance) {
    if (left == right) return 0;
    if ((left.length - right.length).abs() > maxDistance) {
      return maxDistance + 1;
    }

    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 1; i <= left.length; i++) {
      final current = List<int>.filled(right.length + 1, 0);
      current[0] = i;
      var rowMinimum = current[0];
      for (var j = 1; j <= right.length; j++) {
        final substitution = previous[j - 1] +
            (left.codeUnitAt(i - 1) == right.codeUnitAt(j - 1) ? 0 : 1);
        current[j] = math
            .min(
              math.min(current[j - 1] + 1, previous[j] + 1),
              substitution,
            )
            .toInt();
        rowMinimum = math.min(rowMinimum, current[j]).toInt();
      }
      if (rowMinimum > maxDistance) return maxDistance + 1;
      previous = current;
    }
    return previous.last;
  }
}

class _SearchDocument {
  _SearchDocument(this.item)
      : title = normalizeSearchText(item.title),
        compactText = normalizeSearchText(<String>[
          item.title,
          ...item.genres,
          ...item.cast.take(8),
          ...item.keywords,
          item.franchise ?? '',
          item.year.toString(),
          item.typeLabel,
        ].join(' ')),
        titleTokens = normalizeSearchText(item.title)
            .split(' ')
            .where((token) => token.isNotEmpty)
            .toSet(),
        matchTokens = normalizeSearchText(<String>[
          item.title,
          ...item.genres,
          ...item.cast.take(6),
          ...item.keywords,
          item.franchise ?? '',
        ].join(' '))
            .split(' ')
            .where((token) => token.length >= 2)
            .toSet()
            .take(28)
            .toList(growable: false);

  final MediaItem item;
  final String title;
  final String compactText;
  final Set<String> titleTokens;
  final List<String> matchTokens;
}

class _Score {
  const _Score(this.value, this.usedFuzzy);

  final double value;
  final bool usedFuzzy;
}

class _ScoredDocument {
  const _ScoredDocument(this.document, this.score);

  final _SearchDocument document;
  final double score;
}

String normalizeSearchText(String value) {
  var text = value.toLowerCase();
  const replacements = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  replacements.forEach((from, to) => text = text.replaceAll(from, to));
  text = text.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
