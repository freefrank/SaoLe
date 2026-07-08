import 'package:flutter/services.dart';

/// 扫码提示音的 Dart 侧：原生用 ToneGenerator 播一声短哔。
/// 平台不可用时静默失败（提示音不值得报错打断扫码）。
class Beeper {
  const Beeper();

  static const _channel = MethodChannel('saole/beep');

  Future<void> beep() async {
    try {
      await _channel.invokeMethod<void>('beep');
    } on PlatformException {
      // 忽略
    } on MissingPluginException {
      // 忽略
    }
  }
}
