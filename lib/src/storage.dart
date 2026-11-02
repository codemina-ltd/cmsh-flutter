import 'package:shared_preferences/shared_preferences.dart';

/// Small key-value store, so tests can run without a platform.
abstract class CmshStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PreferencesStorage implements CmshStorage {
  static const _prefix = 'cmsh_flutter.';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _preferences.getString('$_prefix$key');

  @override
  Future<void> write(String key, String value) =>
      _preferences.setString('$_prefix$key', value);

  @override
  Future<void> delete(String key) => _preferences.remove('$_prefix$key');
}
