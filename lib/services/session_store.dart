import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'iptv_api_service.dart';

class SessionStore {
  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            FlutterSecureStorage(
              aOptions: AndroidOptions(),
            );

  static const _credentialsKey = 'avo_tv_secure_session_v2';

  final FlutterSecureStorage _storage;

  Future<void> save(LoginCredentials credentials) async {
    await _storage.write(
      key: _credentialsKey,
      value: jsonEncode(credentials.toMap()),
    );
  }

  Future<LoginCredentials?> load() async {
    try {
      final raw = await _storage.read(key: _credentialsKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final credentials = LoginCredentials.fromMap(
        Map<String, dynamic>.from(decoded),
      );
      if (credentials.username.trim().isEmpty ||
          credentials.password.isEmpty) {
        return null;
      }
      return credentials;
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() => _storage.delete(key: _credentialsKey);
}
