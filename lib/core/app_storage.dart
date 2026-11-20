import 'package:shared_preferences/shared_preferences.dart';

/// 轻量本地存储：所有配置/消息/动态都以 JSON 字符串存 shared_preferences。
/// 后续要换成 SQLite/Drift 时，只需要替换 AppState 里的读写实现。
class AppStorage {
  AppStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<AppStorage> open() async =>
      AppStorage(await SharedPreferences.getInstance());

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);
  bool? getBool(String key) => _prefs.getBool(key);
  Future<void> setBool(String key, bool value) => _prefs.setBool(key, value);
  Future<void> remove(String key) => _prefs.remove(key);
  Future<void> clear() => _prefs.clear();
}
