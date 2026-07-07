import 'package:flutter/services.dart';

/// WiFi 一键连接的 Dart 侧：把凭据发给原生（Kotlin 拉起系统添加面板）。
/// 原生失败/不可用时返回 false，由 UI 回退到"复制密码 + 跳设置页"。
class WifiConnect {
  const WifiConnect();

  static const _channel = MethodChannel('saole/wifi');

  Future<bool> connect({
    required String ssid,
    required String password,
    required String security,
    required bool hidden,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>('connect', {
        'ssid': ssid,
        'password': password,
        'security': security,
        'hidden': hidden,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
