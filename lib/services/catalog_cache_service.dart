import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';
import 'iptv_api_service.dart';

class CatalogCacheService {
  static const _fileName = 'avo_catalog_v3.json.gz';

  Future<List<MediaItem>> load(LoginCredentials credentials) async {
    try {
      final file = await _cacheFile();
      if (!await file.exists()) return const [];
      final compressed = await file.readAsBytes();
      final decoded = await compute<List<int>, dynamic>(
        _decodeCompressedCatalog,
        compressed,
      );
      if (decoded is! Map) return const [];
      if ('${decoded['username'] ?? ''}' != credentials.username ||
          '${decoded['providerKey'] ?? ''}' != credentials.providerCacheKey) {
        return const [];
      }
      final rawCatalog = decoded['catalog'];
      if (rawCatalog is! List) return const [];

      final items = <MediaItem>[];
      for (final raw in rawCatalog) {
        if (raw is! Map) continue;
        final item = MediaItem.fromMap(
          raw.map((key, value) => MapEntry('$key', value)),
        );
        if (item.id.isNotEmpty && item.title.isNotEmpty) items.add(item);
      }
      return items;
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(
    LoginCredentials credentials,
    List<MediaItem> catalog,
  ) async {
    if (catalog.isEmpty) return;
    File? temp;
    try {
      final file = await _cacheFile();
      temp = File('${file.path}.tmp');
      final payload = <String, dynamic>{
        'username': credentials.username,
        'providerKey': credentials.providerCacheKey,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'catalog': catalog.map((item) => item.toMap()).toList(growable: false),
      };
      final compressed = await compute<Map<String, dynamic>, List<int>>(
        _encodeCompressedCatalog,
        payload,
      );
      await temp.writeAsBytes(compressed, flush: true);
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      final pending = temp;
      if (pending != null && await pending.exists()) await pending.delete();
      // El caché nunca debe bloquear la navegación ni el inicio de sesión.
    }
  }

  Future<void> clear() async {
    try {
      final directory = await getApplicationSupportDirectory();
      for (final name in const [
        _fileName,
        'avo_catalog_v2.json.gz',
      ]) {
        final file = File(
          '${directory.path}${Platform.pathSeparator}$name',
        );
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      // El cierre de sesión debe continuar aunque falle la limpieza del caché.
    }
  }

  Future<File> _cacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}

dynamic _decodeCompressedCatalog(List<int> compressed) {
  final decodedBytes = gzip.decode(compressed);
  return jsonDecode(utf8.decode(decodedBytes));
}

List<int> _encodeCompressedCatalog(Map<String, dynamic> payload) {
  return gzip.encode(utf8.encode(jsonEncode(payload)));
}
