import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/provider_config.dart';
import '../models/media_item.dart';
import '../models/series_details.dart';
import 'server_directory_service.dart';

class LoginCredentials {
  const LoginCredentials({
    required this.profileName,
    required this.username,
    required this.password,
    this.serverId,
    this.apiScheme,
    this.apiHost,
    this.apiPort,
    this.streamScheme,
    this.streamHost,
    this.streamPort,
    this.allowedOutputFormats = const [],
  });

  final String profileName;
  final String username;
  final String password;
  final String? serverId;
  final String? apiScheme;
  final String? apiHost;
  final int? apiPort;
  final String? streamScheme;
  final String? streamHost;
  final int? streamPort;
  final List<String> allowedOutputFormats;

  bool get hasResolvedProvider => apiHost?.trim().isNotEmpty == true;

  Uri get baseUri {
    final fallback = ProviderConfig.defaultServer;
    return Uri(
      scheme: apiScheme?.trim().isNotEmpty == true
          ? apiScheme!.trim().toLowerCase()
          : fallback.scheme,
      host: apiHost?.trim().isNotEmpty == true
          ? apiHost!.trim()
          : fallback.host,
      port: apiPort ?? fallback.port,
    );
  }

  Uri get streamBaseUri {
    final fallback = baseUri;
    return Uri(
      scheme: streamScheme?.trim().isNotEmpty == true
          ? streamScheme!.trim().toLowerCase()
          : fallback.scheme,
      host: streamHost?.trim().isNotEmpty == true
          ? streamHost!.trim()
          : fallback.host,
      port: streamPort ?? fallback.port,
    );
  }

  ProviderEndpoint get providerEndpoint => ProviderEndpoint(
        id: serverId?.trim().isNotEmpty == true ? serverId!.trim() : 'saved',
        scheme: baseUri.scheme,
        host: baseUri.host,
        port: baseUri.port,
        priority: 500,
      );

  String get providerCacheKey =>
      '${serverId ?? 'unknown'}|${baseUri.scheme}://${baseUri.host}:${baseUri.port}';

  LoginCredentials copyWith({
    String? profileName,
    String? username,
    String? password,
    String? serverId,
    String? apiScheme,
    String? apiHost,
    int? apiPort,
    String? streamScheme,
    String? streamHost,
    int? streamPort,
    List<String>? allowedOutputFormats,
  }) {
    return LoginCredentials(
      profileName: profileName ?? this.profileName,
      username: username ?? this.username,
      password: password ?? this.password,
      serverId: serverId ?? this.serverId,
      apiScheme: apiScheme ?? this.apiScheme,
      apiHost: apiHost ?? this.apiHost,
      apiPort: apiPort ?? this.apiPort,
      streamScheme: streamScheme ?? this.streamScheme,
      streamHost: streamHost ?? this.streamHost,
      streamPort: streamPort ?? this.streamPort,
      allowedOutputFormats: allowedOutputFormats ?? this.allowedOutputFormats,
    );
  }

  LoginCredentials forProvider(ProviderEndpoint endpoint) {
    return LoginCredentials(
      profileName: profileName,
      username: username,
      password: password,
      serverId: endpoint.id,
      apiScheme: endpoint.scheme,
      apiHost: endpoint.host,
      apiPort: endpoint.port,
      streamScheme: endpoint.scheme,
      streamHost: endpoint.host,
      streamPort: endpoint.port,
      allowedOutputFormats: allowedOutputFormats,
    );
  }

  Map<String, dynamic> toMap() => {
        'profileName': profileName,
        'username': username,
        'password': password,
        'serverId': serverId,
        'apiScheme': apiScheme,
        'apiHost': apiHost,
        'apiPort': apiPort,
        'streamScheme': streamScheme,
        'streamHost': streamHost,
        'streamPort': streamPort,
        'allowedOutputFormats': allowedOutputFormats,
      };

  factory LoginCredentials.fromMap(Map<String, dynamic> map) {
    final formatsRaw = map['allowedOutputFormats'];
    final formats = formatsRaw is List
        ? formatsRaw.map((value) => '$value').toList()
        : const <String>[];
    final username = '${map['username'] ?? ''}';

    return LoginCredentials(
      profileName: '${map['profileName'] ?? username}',
      username: username,
      password: '${map['password'] ?? ''}',
      serverId: _nullableString(map['serverId']),
      apiScheme: _nullableString(map['apiScheme']),
      apiHost: _nullableString(map['apiHost']),
      apiPort: int.tryParse('${map['apiPort'] ?? ''}'),
      streamScheme: _nullableString(map['streamScheme']),
      streamHost: _nullableString(map['streamHost']),
      streamPort: int.tryParse('${map['streamPort'] ?? ''}'),
      allowedOutputFormats: formats,
    );
  }

  static String? _nullableString(dynamic value) {
    final text = '$value'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return null;
    return text;
  }
}

class AuthResult {
  const AuthResult({
    required this.success,
    required this.message,
    this.accountName,
    this.resolvedCredentials,
  });

  final bool success;
  final String message;
  final String? accountName;
  final LoginCredentials? resolvedCredentials;
}

class IptvApiService {
  IptvApiService({
    http.Client? client,
    ServerDirectoryService? serverDirectory,
  })  : _client = client ?? http.Client(),
        _serverDirectory = serverDirectory ?? ServerDirectoryService();

  final http.Client _client;
  final ServerDirectoryService _serverDirectory;

  static const _headers = <String, String>{
    'Accept': 'application/json,text/plain,*/*',
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 AVO-TV/0.7.1',
  };

  Future<AuthResult> authenticate(LoginCredentials credentials) async {
    final candidates = await _serverDirectory.loadCandidates(
      remembered: credentials.hasResolvedProvider
          ? credentials.providerEndpoint
          : null,
    );
    var invalidCredentials = false;
    var reachableServer = false;

    final attempts = <String, Future<AuthResult>>{
      for (final endpoint in candidates)
        endpoint.endpointKey: _authenticateAt(
          credentials.forProvider(endpoint),
        ),
    };

    for (final endpoint in candidates) {
      final result = await attempts[endpoint.endpointKey]!;
      if (result.success) return result;
      if (result.message == _invalidCredentialsMessage) {
        invalidCredentials = true;
        reachableServer = true;
      } else if (result.message == _inactiveAccountMessage) {
        invalidCredentials = true;
        reachableServer = true;
      } else if (result.message == _invalidResponseMessage) {
        reachableServer = true;
      }
    }

    if (invalidCredentials || reachableServer) {
      return const AuthResult(
        success: false,
        message: 'El usuario o la contraseña no son válidos.',
      );
    }
    return const AuthResult(
      success: false,
      message: 'No fue posible conectar con el servicio de AVO TV. Intenta nuevamente.',
    );
  }

  static const _invalidCredentialsMessage = '__invalid_credentials__';
  static const _inactiveAccountMessage = '__inactive_account__';
  static const _invalidResponseMessage = '__invalid_response__';

  Future<AuthResult> _authenticateAt(LoginCredentials credentials) async {
    try {
      final response = await _client
          .get(_playerApiUri(credentials), headers: _headers)
          .timeout(const Duration(seconds: 9));

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const AuthResult(
          success: false,
          message: _invalidCredentialsMessage,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return AuthResult(
          success: false,
          message: 'El servicio respondió con código ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        return const AuthResult(
          success: false,
          message: _invalidResponseMessage,
        );
      }

      final userInfo = decoded['user_info'];
      if (userInfo is! Map) {
        return const AuthResult(
          success: false,
          message: _invalidCredentialsMessage,
        );
      }

      final authValue = '${userInfo['auth'] ?? ''}'.toLowerCase();
      final status = '${userInfo['status'] ?? ''}'.toLowerCase();
      final active = authValue == '1' ||
          authValue == 'true' ||
          status == 'active' ||
          status == 'activo';

      if (!active) {
        return const AuthResult(
          success: false,
          message: _inactiveAccountMessage,
        );
      }

      final resolved = _resolveStreamCredentials(
        credentials,
        decoded['server_info'],
        userInfo,
      );

      return AuthResult(
        success: true,
        message: 'Acceso correcto.',
        accountName: credentials.profileName.trim().isNotEmpty
            ? credentials.profileName.trim()
            : '${userInfo['username'] ?? credentials.username}',
        resolvedCredentials: resolved,
      );
    } on FormatException {
      return const AuthResult(
        success: false,
        message: _invalidResponseMessage,
      );
    } on http.ClientException {
      return const AuthResult(
        success: false,
        message: 'No fue posible conectar.',
      );
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'El servicio no respondió a tiempo.',
      );
    }
  }

  LoginCredentials _resolveStreamCredentials(
    LoginCredentials credentials,
    dynamic serverInfoRaw,
    Map userInfo,
  ) {
    var scheme = credentials.streamBaseUri.scheme;
    var host = credentials.streamBaseUri.host;
    var port = credentials.streamBaseUri.port;

    if (serverInfoRaw is Map) {
      final protocol = '${serverInfoRaw['server_protocol'] ?? ''}'
          .trim()
          .toLowerCase();
      if (protocol == 'http' || protocol == 'https') scheme = protocol;

      final rawUrl = _firstNonEmpty([
        '${serverInfoRaw['url'] ?? ''}',
        '${serverInfoRaw['server'] ?? ''}',
      ]);
      if (rawUrl.isNotEmpty) {
        final parsed = Uri.tryParse(
          rawUrl.startsWith('http://') || rawUrl.startsWith('https://')
              ? rawUrl
              : '$scheme://$rawUrl',
        );
        if (parsed != null && parsed.host.isNotEmpty) {
          host = parsed.host;
          if (parsed.hasPort) port = parsed.port;
          if (parsed.scheme == 'http' || parsed.scheme == 'https') {
            scheme = parsed.scheme;
          }
        }
      }

      final preferredPortRaw = scheme == 'https'
          ? serverInfoRaw['https_port'] ?? serverInfoRaw['port']
          : serverInfoRaw['port'];
      final preferredPort = int.tryParse('$preferredPortRaw');
      if (preferredPort != null && preferredPort > 0 && preferredPort <= 65535) {
        port = preferredPort;
      }
    }

    final formats = _parseOutputFormats(userInfo['allowed_output_formats']);
    return credentials.copyWith(
      streamScheme: scheme,
      streamHost: host,
      streamPort: port,
      allowedOutputFormats: formats,
    );
  }

  List<String> _parseOutputFormats(dynamic raw) {
    final values = raw is List ? raw : '$raw'.split(',');
    return values
        .map((value) => '$value'.trim().toLowerCase())
        .where((value) => value.isNotEmpty && value != 'null')
        .toSet()
        .toList();
  }

  Future<List<MediaItem>> loadCatalog(LoginCredentials credentials) async {
    final results = await Future.wait<dynamic>([
      _getJson(_playerApiUri(credentials, action: 'get_vod_categories')),
      _getJson(_playerApiUri(credentials, action: 'get_series_categories')),
      _getJson(_playerApiUri(credentials, action: 'get_live_categories')),
      _getJson(_playerApiUri(credentials, action: 'get_vod_streams')),
      _getJson(_playerApiUri(credentials, action: 'get_series')),
      _getJson(_playerApiUri(credentials, action: 'get_live_streams')),
    ]);

    final movieCategories = _categoryMap(results[0]);
    final seriesCategories = _categoryMap(results[1]);
    final liveCategories = _categoryMap(results[2]);

    final catalog = <MediaItem>[
      ..._mapMovies(credentials, results[3], movieCategories),
      ..._mapSeries(credentials, results[4], seriesCategories),
      ..._mapLive(credentials, results[5], liveCategories),
    ];

    catalog.sort((a, b) {
      if (a.type == MediaType.live && b.type != MediaType.live) return 1;
      if (b.type == MediaType.live && a.type != MediaType.live) return -1;
      if (a.isNew != b.isNew) return a.isNew ? -1 : 1;
      return b.rating.compareTo(a.rating);
    });
    return catalog;
  }

  Future<String> loadVodTrailer(
    LoginCredentials credentials,
    String vodId,
  ) async {
    final raw = await _getJson(
      _playerApiUri(
        credentials,
        action: 'get_vod_info',
        extra: {'vod_id': vodId},
      ),
    );
    if (raw is! Map) return '';
    final info = raw['info'];
    if (info is Map) {
      final value = _trailerUrl(info);
      if (value.isNotEmpty) return value;
    }
    final movieData = raw['movie_data'];
    if (movieData is Map) {
      final value = _trailerUrl(movieData);
      if (value.isNotEmpty) return value;
    }
    return _trailerUrl(raw);
  }

  Future<SeriesDetails> loadSeriesDetails(
    LoginCredentials credentials,
    String seriesId,
  ) async {
    final raw = await _getJson(
      _playerApiUri(
        credentials,
        action: 'get_series_info',
        extra: {'series_id': seriesId},
      ),
    );

    if (raw is! Map) {
      throw const FormatException('El servidor no devolvió los episodios.');
    }

    final episodesRaw = raw['episodes'];
    final seasons = <int, List<EpisodeItem>>{};

    if (episodesRaw is Map) {
      for (final entry in episodesRaw.entries) {
        final seasonNumber = int.tryParse('${entry.key}') ?? 0;
        final episodes = _episodeList(
          credentials,
          entry.value,
          fallbackSeason: seasonNumber,
        );
        if (episodes.isNotEmpty) {
          seasons[seasonNumber <= 0 ? 1 : seasonNumber] = episodes;
        }
      }
    } else if (episodesRaw is List) {
      for (final episode in _episodeList(
        credentials,
        episodesRaw,
        fallbackSeason: 1,
      )) {
        seasons.putIfAbsent(episode.seasonNumber, () => []).add(episode);
      }
    }

    for (final episodes in seasons.values) {
      episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    }

    if (seasons.isEmpty) {
      throw const FormatException(
        'Esta serie no incluye temporadas o episodios reproducibles.',
      );
    }

    return SeriesDetails(seriesId: seriesId, seasons: seasons);
  }

  Uri _playerApiUri(
    LoginCredentials credentials, {
    String? action,
    Map<String, String> extra = const {},
  }) {
    final base = credentials.baseUri;
    return base.replace(
      pathSegments: [
        ...base.pathSegments.where((segment) => segment.isNotEmpty),
        'player_api.php',
      ],
      queryParameters: {
        'username': credentials.username,
        'password': credentials.password,
        if (action != null) 'action': action,
        ...extra,
      },
    );
  }

  Future<dynamic> _getJson(Uri uri) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 120));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final bytes = response.bodyBytes;
          if (bytes.length > 256 * 1024) {
            return compute<List<int>, dynamic>(_decodeJsonBytes, bytes);
          }
          return _decodeJsonBytes(bytes);
        }
      } catch (_) {
        // Retry once because very large catalog responses can be slow.
      }
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    return null;
  }

  Map<String, String> _categoryMap(dynamic raw) {
    if (raw is! List) return const {};
    final map = <String, String>{};
    for (final entry in raw) {
      if (entry is Map) {
        final id = '${entry['category_id'] ?? ''}';
        final name = '${entry['category_name'] ?? ''}'.trim();
        if (id.isNotEmpty && name.isNotEmpty) map[id] = name;
      }
    }
    return map;
  }

  List<MediaItem> _mapMovies(
    LoginCredentials credentials,
    dynamic raw,
    Map<String, String> categories,
  ) {
    if (raw is! List) return const [];
    final items = <MediaItem>[];

    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = '${entry['stream_id'] ?? ''}';
      final title = '${entry['name'] ?? ''}'.trim();
      if (id.isEmpty || title.isEmpty) continue;

      final extension = _safeExtension(
        '${entry['container_extension'] ?? 'mp4'}',
        fallback: 'mp4',
      );
      final category = categories['${entry['category_id'] ?? ''}'];
      final added = int.tryParse('${entry['added'] ?? ''}');
      final poster = _normalizeArtworkUrl(
        credentials,
        '${entry['stream_icon'] ?? entry['cover'] ?? ''}',
      );
      final direct = '${entry['direct_source'] ?? ''}'.trim();

      items.add(
        MediaItem(
          id: 'movie-$id',
          providerId: id,
          title: title,
          type: MediaType.movie,
          year: _extractYear(entry),
          rating: _extractRating(entry),
          description: _cleanText(
            entry['plot'] ?? entry['description'],
            fallback: 'Sin descripción disponible.',
          ),
          posterUrl: poster,
          backdropUrl: _normalizeArtworkUrl(
            credentials,
            _backdrop(entry, poster),
          ),
          genres: [if (category != null && category.isNotEmpty) category],
          cast: _splitList(entry['cast']),
          keywords: _titleKeywords(title),
          durationLabel: _durationLabel(entry, fallback: 'Película'),
          franchise: _guessFranchise(title),
          isNew: _isRecentUnix(added),
          addedAt: added ?? 0,
          trailerUrl: _trailerUrl(entry),
          streamUrls: _uniqueUrls([
            if (_isHttpUrl(direct)) direct,
            ..._streamCandidates(
              credentials,
              kind: 'movie',
              id: id,
              extensions: [extension, 'mp4', 'mkv'],
            ),
          ]),
        ),
      );
    }
    return items;
  }

  List<MediaItem> _mapSeries(
    LoginCredentials credentials,
    dynamic raw,
    Map<String, String> categories,
  ) {
    if (raw is! List) return const [];
    final items = <MediaItem>[];

    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = '${entry['series_id'] ?? ''}';
      final title = '${entry['name'] ?? ''}'.trim();
      if (id.isEmpty || title.isEmpty) continue;

      final category = categories['${entry['category_id'] ?? ''}'];
      final added = int.tryParse(
        '${entry['last_modified'] ?? entry['added'] ?? ''}',
      );
      final poster = _normalizeArtworkUrl(
        credentials,
        '${entry['cover'] ?? entry['stream_icon'] ?? ''}',
      );

      items.add(
        MediaItem(
          id: 'series-$id',
          providerId: id,
          title: title,
          type: MediaType.series,
          year: _extractYear(entry),
          rating: _extractRating(entry),
          description: _cleanText(
            entry['plot'] ?? entry['description'],
            fallback: 'Sin descripción disponible.',
          ),
          posterUrl: poster,
          backdropUrl: _normalizeArtworkUrl(
            credentials,
            _backdrop(entry, poster),
          ),
          genres: [if (category != null && category.isNotEmpty) category],
          cast: _splitList(entry['cast']),
          keywords: _titleKeywords(title),
          durationLabel: 'Serie',
          franchise: _guessFranchise(title),
          isNew: _isRecentUnix(added),
          addedAt: added ?? 0,
          trailerUrl: _trailerUrl(entry),
        ),
      );
    }
    return items;
  }

  List<MediaItem> _mapLive(
    LoginCredentials credentials,
    dynamic raw,
    Map<String, String> categories,
  ) {
    if (raw is! List) return const [];
    final items = <MediaItem>[];
    final extensions = _liveExtensions(credentials);

    for (final entry in raw) {
      if (entry is! Map) continue;
      final id = '${entry['stream_id'] ?? ''}';
      final title = '${entry['name'] ?? ''}'.trim();
      if (id.isEmpty || title.isEmpty) continue;

      final category = categories['${entry['category_id'] ?? ''}'];
      final poster = _normalizeArtworkUrl(
        credentials,
        '${entry['stream_icon'] ?? ''}',
      );
      final direct = '${entry['direct_source'] ?? ''}'.trim();
      final added = int.tryParse('${entry['added'] ?? ''}');

      items.add(
        MediaItem(
          id: 'live-$id',
          providerId: id,
          title: title,
          type: MediaType.live,
          year: DateTime.now().year,
          rating: 0,
          description: category == null || category.isEmpty
              ? 'Canal transmitiendo en vivo.'
              : 'Canal en vivo • $category',
          posterUrl: poster,
          backdropUrl: poster,
          genres: [if (category != null && category.isNotEmpty) category],
          cast: const [],
          keywords: _titleKeywords(title),
          durationLabel: 'EN VIVO',
          addedAt: added ?? 0,
          streamUrls: _uniqueUrls([
            if (_isHttpUrl(direct)) direct,
            ..._streamCandidates(
              credentials,
              kind: 'live',
              id: id,
              extensions: extensions,
            ),
            ..._shortLiveCandidates(credentials, id, extensions),
          ]),
        ),
      );
    }
    return items;
  }

  List<EpisodeItem> _episodeList(
    LoginCredentials credentials,
    dynamic raw, {
    required int fallbackSeason,
  }) {
    if (raw is! List) return const [];
    final result = <EpisodeItem>[];

    for (var index = 0; index < raw.length; index++) {
      final entry = raw[index];
      if (entry is! Map) continue;
      final id = '${entry['id'] ?? entry['stream_id'] ?? ''}';
      if (id.isEmpty) continue;

      final info = entry['info'] is Map ? entry['info'] as Map : const {};
      final season = int.tryParse(
            '${entry['season'] ?? info['season'] ?? fallbackSeason}',
          ) ??
          fallbackSeason;
      final episodeNumber = int.tryParse(
            '${entry['episode_num'] ?? info['episode_num'] ?? index + 1}',
          ) ??
          index + 1;
      final title = _cleanText(
        entry['title'] ?? info['name'],
        fallback: 'Episodio $episodeNumber',
      );
      final extension = _safeExtension(
        '${entry['container_extension'] ?? info['container_extension'] ?? 'mp4'}',
        fallback: 'mp4',
      );
      final direct =
          '${entry['direct_source'] ?? info['direct_source'] ?? ''}'.trim();
      final image = _firstNonEmpty([
        '${info['movie_image'] ?? ''}',
        '${info['cover_big'] ?? ''}',
        '${info['cover'] ?? ''}',
      ]);

      result.add(
        EpisodeItem(
          id: 'episode-$id',
          title: title,
          seasonNumber: season <= 0 ? 1 : season,
          episodeNumber: episodeNumber,
          description: _cleanText(
            info['plot'] ?? entry['plot'] ?? info['description'],
            fallback: 'Sin descripción disponible.',
          ),
          durationLabel: _durationLabel(info, fallback: 'Episodio'),
          imageUrl: image,
          rating: _extractRating(info),
          streamUrls: _uniqueUrls([
            if (_isHttpUrl(direct)) direct,
            ..._streamCandidates(
              credentials,
              kind: 'series',
              id: id,
              extensions: [extension, 'mp4', 'mkv'],
            ),
          ]),
        ),
      );
    }
    return result;
  }

  List<String> _liveExtensions(LoginCredentials credentials) {
    final allowed = credentials.allowedOutputFormats
        .map((value) => value.toLowerCase())
        .toSet();
    if (allowed.contains('m3u8') && !allowed.contains('ts')) {
      return const ['m3u8', 'ts'];
    }
    return const ['ts', 'm3u8'];
  }

  List<Uri> _streamBases(LoginCredentials credentials) {
    final values = <Uri>[];
    for (final base in [credentials.streamBaseUri, credentials.baseUri]) {
      if (!values.any(
        (existing) =>
            existing.scheme == base.scheme &&
            existing.host == base.host &&
            existing.port == base.port,
      )) {
        values.add(base);
      }
    }
    return values;
  }

  List<String> _streamCandidates(
    LoginCredentials credentials, {
    required String kind,
    required String id,
    required List<String> extensions,
  }) {
    final values = <String>[];
    for (final base in _streamBases(credentials)) {
      for (final extension in extensions.toSet()) {
        values.add(
          base
              .replace(
                pathSegments: [
                  ...base.pathSegments.where((segment) => segment.isNotEmpty),
                  kind,
                  credentials.username,
                  credentials.password,
                  '$id.$extension',
                ],
                query: null,
              )
              .toString(),
        );
      }
    }
    return values;
  }

  List<String> _shortLiveCandidates(
    LoginCredentials credentials,
    String id,
    List<String> extensions,
  ) {
    final values = <String>[];
    for (final base in _streamBases(credentials)) {
      for (final extension in extensions.toSet()) {
        values.add(
          base
              .replace(
                pathSegments: [
                  ...base.pathSegments.where((segment) => segment.isNotEmpty),
                  credentials.username,
                  credentials.password,
                  '$id.$extension',
                ],
                query: null,
              )
              .toString(),
        );
      }
      values.add(
        base
            .replace(
              pathSegments: [
                ...base.pathSegments.where((segment) => segment.isNotEmpty),
                credentials.username,
                credentials.password,
                id,
              ],
              query: null,
            )
            .toString(),
      );
    }
    return values;
  }


  String _normalizeArtworkUrl(
    LoginCredentials credentials,
    String raw,
  ) {
    final value = raw.trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return '';
    final base = credentials.streamBaseUri;
    if (value.startsWith('//')) return '${base.scheme}:$value';

    final parsed = Uri.tryParse(value);
    if (parsed != null &&
        (parsed.scheme == 'http' || parsed.scheme == 'https') &&
        parsed.host.isNotEmpty) {
      return parsed.toString();
    }

    if (!value.contains('/') && value.contains('.')) {
      return '${base.scheme}://$value';
    }

    try {
      return base.resolve(value).toString();
    } catch (_) {
      return value;
    }
  }

  String _backdrop(Map entry, String fallback) {
    final raw = entry['backdrop_path'];
    if (raw is List && raw.isNotEmpty) return '${raw.first}';
    if (raw is String && raw.trim().isNotEmpty) return raw;
    return fallback;
  }

  int _extractYear(Map entry) {
    final candidates = [
      entry['releaseDate'],
      entry['release_date'],
      entry['year'],
      entry['releasedate'],
      entry['air_date'],
    ];
    for (final value in candidates) {
      final match = RegExp(r'(19|20)\d{2}').firstMatch('$value');
      if (match != null) return int.parse(match.group(0)!);
    }
    return DateTime.now().year;
  }

  double _extractRating(Map entry) {
    final raw = entry['rating_5based'] ?? entry['rating'] ?? 0;
    final parsed = double.tryParse('$raw') ?? 0;
    if (parsed <= 5 && parsed > 0) return parsed * 2;
    return parsed.clamp(0, 10).toDouble();
  }

  String _durationLabel(Map entry, {required String fallback}) {
    final rawDuration = '${entry['duration'] ?? ''}'.trim();
    if (rawDuration.isNotEmpty && rawDuration.toLowerCase() != 'null') {
      return rawDuration;
    }
    final seconds = int.tryParse('${entry['duration_secs'] ?? ''}');
    if (seconds == null || seconds <= 0) return fallback;
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '$hours h ${minutes.toString().padLeft(2, '0')} min';
    return '$minutes min';
  }

  List<String> _splitList(dynamic value) {
    return '$value'
        .split(RegExp(r'[,|/]'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty && item.toLowerCase() != 'null')
        .take(10)
        .toList();
  }

  List<String> _titleKeywords(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-záéíóúüñ0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 3)
        .take(10)
        .toList();
  }

  String? _guessFranchise(String title) {
    final cleaned = title.split(RegExp(r'[:\-–—]')).first.trim();
    if (cleaned.split(' ').length <= 5 && cleaned.length >= 5) return cleaned;
    return null;
  }

  bool _isRecentUnix(int? seconds) {
    if (seconds == null || seconds <= 0) return false;
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    return DateTime.now().difference(date).inDays <= 120;
  }

  String _trailerUrl(Map entry) {
    final raw = _firstNonEmpty([
      '${entry['youtube_trailer'] ?? ''}',
      '${entry['trailer'] ?? ''}',
      '${entry['trailer_url'] ?? ''}',
    ]);
    if (raw.isEmpty) return '';
    final uri = Uri.tryParse(raw);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return raw;
    }
    final id = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    if (id.isEmpty) return '';
    return 'https://www.youtube.com/watch?v=$id';
  }

  String _safeExtension(String raw, {required String fallback}) {
    final cleaned = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  List<String> _uniqueUrls(Iterable<String> urls) {
    final values = <String>[];
    for (final value in urls) {
      final clean = value.trim();
      if (clean.isNotEmpty && !values.contains(clean)) values.add(clean);
    }
    return values;
  }

  String _cleanText(dynamic value, {required String fallback}) {
    final text = '$value'.trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return fallback;
    return text;
  }

  String _firstNonEmpty(Iterable<String> values) {
    for (final value in values) {
      final clean = value.trim();
      if (clean.isNotEmpty && clean.toLowerCase() != 'null') return clean;
    }
    return '';
  }

  void dispose() {
    _client.close();
    _serverDirectory.dispose();
  }
}


dynamic _decodeJsonBytes(List<int> bytes) {
  return jsonDecode(utf8.decode(bytes));
}
