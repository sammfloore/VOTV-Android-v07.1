import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/provider_config.dart';

class ServerDirectorySnapshot {
  const ServerDirectorySnapshot({
    required this.version,
    required this.servers,
  });

  final int version;
  final List<ProviderEndpoint> servers;

  Map<String, dynamic> toMap() => {
        'schema': 1,
        'version': version,
        'servers': servers.map((item) => item.toMap()).toList(growable: false),
      };

  static ServerDirectorySnapshot? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final schema = int.tryParse('${raw['schema'] ?? 1}') ?? 1;
    final version = int.tryParse('${raw['version'] ?? ''}');
    final serversRaw = raw['servers'];
    if (schema != 1 || version == null || version <= 0 || serversRaw is! List) {
      return null;
    }

    final byId = <String, ProviderEndpoint>{};
    final endpointKeys = <String>{};
    for (final value in serversRaw.take(8)) {
      final endpoint = ProviderEndpoint.tryParse(value);
      if (endpoint == null) continue;
      if (byId.containsKey(endpoint.id)) continue;
      if (!endpointKeys.add(endpoint.endpointKey)) continue;
      byId[endpoint.id] = endpoint;
    }

    final enabled = byId.values.where((item) => item.enabled).toList()
      ..sort((a, b) {
        final priority = a.priority.compareTo(b.priority);
        return priority != 0 ? priority : a.id.compareTo(b.id);
      });
    if (enabled.isEmpty) return null;

    return ServerDirectorySnapshot(version: version, servers: enabled);
  }
}

class ServerDirectoryService {
  ServerDirectoryService({
    http.Client? client,
    List<Uri>? remoteConfigUris,
  })  : _client = client ?? http.Client(),
        _remoteConfigUris = remoteConfigUris ?? ProviderConfig.remoteConfigUris;

  static const _cacheKey = 'avo_tv_server_directory_v1';
  static const _maxConfigBytes = 64 * 1024;

  final http.Client _client;
  final List<Uri> _remoteConfigUris;

  Future<List<ProviderEndpoint>> loadCandidates({
    ProviderEndpoint? remembered,
  }) async {
    final cached = await _loadCached();
    final remote = await _downloadRemote(
      minimumVersion: cached?.version ?? 0,
    );
    final selected = remote ?? cached;

    final candidates = <ProviderEndpoint>[
      ...(selected?.servers ?? ProviderConfig.fallbackServers),
    ];

    if (remembered != null &&
        remembered.enabled &&
        !candidates.any((item) => item.endpointKey == remembered.endpointKey)) {
      candidates.add(remembered);
    }

    candidates.sort((a, b) {
      final priority = a.priority.compareTo(b.priority);
      return priority != 0 ? priority : a.id.compareTo(b.id);
    });
    return List.unmodifiable(candidates);
  }

  Future<ServerDirectorySnapshot?> _downloadRemote({
    required int minimumVersion,
  }) async {
    for (final baseUri in _remoteConfigUris) {
      if (baseUri.scheme != 'https' || baseUri.host.isEmpty) continue;
      try {
        final cacheBucket = DateTime.now().millisecondsSinceEpoch ~/ 300000;
        final uri = baseUri.replace(
          queryParameters: {
            ...baseUri.queryParameters,
            'v': '$cacheBucket',
          },
        );
        final response = await _client.get(
          uri,
          headers: const {
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            'User-Agent': 'AVO-TV-Android/0.7.1',
          },
        ).timeout(const Duration(seconds: 4));

        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        if (response.bodyBytes.isEmpty ||
            response.bodyBytes.length > _maxConfigBytes) {
          continue;
        }
        final raw = jsonDecode(utf8.decode(response.bodyBytes));
        final snapshot = ServerDirectorySnapshot.tryParse(raw);
        if (snapshot == null || snapshot.version < minimumVersion) continue;
        await _saveCached(snapshot);
        return snapshot;
      } catch (_) {
        // Se intenta la siguiente URL y después la copia guardada.
      }
    }
    return null;
  }

  Future<ServerDirectorySnapshot?> _loadCached() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      return ServerDirectorySnapshot.tryParse(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCached(ServerDirectorySnapshot snapshot) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_cacheKey, jsonEncode(snapshot.toMap()));
    } catch (_) {
      // La detección sigue funcionando con la configuración descargada.
    }
  }

  void dispose() => _client.close();
}
