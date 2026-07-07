import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';

/// 用户设置：内存缓存 + shared_preferences 持久化，改动即写盘并通知。
class SettingsStore extends ChangeNotifier {
  final SharedPreferences _prefs;
  SettingsStore(this._prefs);

  static Future<SettingsStore> forApp() async =>
      SettingsStore(await SharedPreferences.getInstance());

  static const _kAutoOpen = 'auto_open';
  static const _kHaptics = 'haptics';
  static const _kBeep = 'beep';
  static const _kKeepHistory = 'keep_history';
  static const _kContinuous = 'continuous';
  static const _kBrightness = 'brightness';

  /// 扫到 URL/AppLink 即自动打开（默认关，防钓鱼）。
  bool get autoOpen => _prefs.getBool(_kAutoOpen) ?? false;
  set autoOpen(bool v) => _set(_kAutoOpen, v);

  bool get haptics => _prefs.getBool(_kHaptics) ?? true;
  set haptics(bool v) => _set(_kHaptics, v);

  bool get beep => _prefs.getBool(_kBeep) ?? false;
  set beep(bool v) => _set(_kBeep, v);

  bool get keepHistory => _prefs.getBool(_kKeepHistory) ?? true;
  set keepHistory(bool v) => _set(_kKeepHistory, v);

  bool get continuous => _prefs.getBool(_kContinuous) ?? false;
  set continuous(bool v) => _set(_kContinuous, v);

  SaoBrightness get brightness =>
      SaoBrightness.values[_prefs.getInt(_kBrightness) ?? 0];
  set brightness(SaoBrightness v) {
    _prefs.setInt(_kBrightness, v.index);
    notifyListeners();
  }

  void _set(String key, bool v) {
    _prefs.setBool(key, v);
    notifyListeners();
  }
}
