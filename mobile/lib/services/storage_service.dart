import 'package:get/get.dart' as getx;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_storage/get_storage.dart';

class StorageService extends getx.GetxService {
  final _secureStorage = const FlutterSecureStorage();
  final _box = GetStorage();

  // Keys
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userIdKey = 'user_id';
  static const String _usernameKey = 'username';
  static const String _languageKey = 'language';
  static const String _themeKey = 'theme';
  static const String _soundEnabledKey = 'sound_enabled';
  static const String _vibrationEnabledKey = 'vibration_enabled';

  // ============================================================================
  // SECURE STORAGE (TOKENS)
  // ============================================================================

  Future<void> setAccessToken(String token) async {
    await _secureStorage.write(key: _accessTokenKey, value: token);
  }

  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: _accessTokenKey);
  }

  Future<void> setRefreshToken(String token) async {
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: _refreshTokenKey);
  }

  Future<void> clearAuth() async {
    await _secureStorage.delete(key: _accessTokenKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    _box.remove(_userIdKey);
    _box.remove(_usernameKey);
  }

  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // ============================================================================
  // REGULAR STORAGE (SETTINGS & CACHE)
  // ============================================================================

  // User info cache
  void setUserId(String userId) => _box.write(_userIdKey, userId);
  String? getUserId() => _box.read(_userIdKey);

  void setUsername(String username) => _box.write(_usernameKey, username);
  String? getUsername() => _box.read(_usernameKey);

  // Settings
  void setLanguage(String language) => _box.write(_languageKey, language);
  String getLanguage() => _box.read(_languageKey) ?? 'en';

  void setTheme(String theme) => _box.write(_themeKey, theme);
  String getTheme() => _box.read(_themeKey) ?? 'dark';

  void setSoundEnabled(bool enabled) => _box.write(_soundEnabledKey, enabled);
  bool isSoundEnabled() => _box.read(_soundEnabledKey) ?? true;

  void setVibrationEnabled(bool enabled) =>
      _box.write(_vibrationEnabledKey, enabled);
  bool isVibrationEnabled() => _box.read(_vibrationEnabledKey) ?? true;

  // Generic methods
  void write<T>(String key, T value) => _box.write(key, value);
  T? read<T>(String key) => _box.read<T>(key);
  void remove(String key) => _box.remove(key);

  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
    await _box.erase();
  }
}
