import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LocalStore {
  static const _favoritesKey = 'favorites';
  static const _progressKey = 'progress';
  static const _historyKey = 'history';
  static const _episodeProgressKey = 'episode_progress';
  static const _lastEpisodeKey = 'last_episode_by_series';
  static const _profileNameKey = 'profile_name';
  static const _usernameKey = 'username';
  static const _catalogRefreshKey = 'catalog_refresh_at';
  static const _pictureInPictureEnabledKey = 'picture_in_picture_enabled';
  static const _pictureInPictureAutoEnterKey =
      'picture_in_picture_auto_enter';
  static const _playbackVolumeKey = 'playback_volume';
  static const _subtitleScaleKey = 'subtitle_scale';

  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
  }

  Future<Set<String>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_favoritesKey) ?? const []).toSet();
  }

  Future<Map<String, double>> loadProgress() => _loadDoubleMap(_progressKey);

  Future<Map<String, double>> loadEpisodeProgress() =>
      _loadDoubleMap(_episodeProgressKey);

  Future<Map<String, String>> loadLastEpisodes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastEpisodeKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return decoded.map((key, value) => MapEntry('$key', '$value'));
    } catch (_) {
      return {};
    }
  }

  Future<Map<String, double>> _loadDoubleMap(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final result = <String, double>{};
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is num) result['${entry.key}'] = value.toDouble();
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<List<String>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_historyKey) ?? [];
  }

  Future<void> saveFavorites(Set<String> favorites) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, favorites.toList());
  }

  Future<void> saveProgress(Map<String, double> progress) =>
      _saveDoubleMap(_progressKey, progress);

  Future<void> saveEpisodeProgress(Map<String, double> progress) =>
      _saveDoubleMap(_episodeProgressKey, progress);

  Future<void> _saveDoubleMap(String key, Map<String, double> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(values));
  }

  Future<void> saveLastEpisodes(Map<String, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastEpisodeKey, jsonEncode(values));
  }

  Future<void> saveHistory(List<String> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, history.take(150).toList());
  }

  Future<void> saveRememberedLogin({
    required String profileName,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileNameKey, profileName);
    await prefs.setString(_usernameKey, username);
  }

  Future<Map<String, String>> loadRememberedLogin() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'profileName': prefs.getString(_profileNameKey) ?? '',
      'username': prefs.getString(_usernameKey) ?? '',
    };
  }

  Future<DateTime?> loadCatalogRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_catalogRefreshKey);
    if (value == null || value <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<void> saveCatalogRefresh(DateTime value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_catalogRefreshKey, value.millisecondsSinceEpoch);
  }

  Future<void> clearCatalogRefresh() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_catalogRefreshKey);
  }

  Future<void> clearRememberedLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileNameKey);
    await prefs.remove(_usernameKey);
  }

  Future<bool> loadPictureInPictureEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pictureInPictureEnabledKey) ?? true;
  }

  Future<bool> loadPictureInPictureAutoEnter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pictureInPictureAutoEnterKey) ?? true;
  }

  Future<void> savePictureInPictureEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pictureInPictureEnabledKey, value);
  }

  Future<void> savePictureInPictureAutoEnter(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pictureInPictureAutoEnterKey, value);
  }

  Future<double> loadPlaybackVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_playbackVolumeKey) ?? 100.0)
        .clamp(0.0, 200.0)
        .toDouble();
  }

  Future<void> savePlaybackVolume(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _playbackVolumeKey,
      value.clamp(0.0, 200.0).toDouble(),
    );
  }

  Future<double> loadSubtitleScale() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getDouble(_subtitleScaleKey) ?? 1.0)
        .clamp(0.75, 2.0)
        .toDouble();
  }

  Future<void> saveSubtitleScale(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _subtitleScaleKey,
      value.clamp(0.75, 2.0).toDouble(),
    );
  }
}
