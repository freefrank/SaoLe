import 'package:url_launcher/url_launcher.dart';

/// url_launcher 的薄封装：打开 URL / App 链接 / FIDO 链接，唤不起返回 false 由 UI 降级。
class Launcher {
  const Launcher();

  /// 外部打开一个 URI 字符串。畸形串或无 app 处理 → false（不抛）。
  /// 不用 canLaunchUrl 预检：它受 Android 11+ 包可见性限制，会对未在
  /// `<queries>` 声明的自定义 scheme（fido/weixin/…）误报为不可开。
  Future<bool> open(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<bool> dial(String number) => open('tel:$number');
  Future<bool> email(String address) => open('mailto:$address');
}
