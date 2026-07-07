import 'package:url_launcher/url_launcher.dart';

/// url_launcher 的薄封装：打开 URL / App 链接 / FIDO 链接，唤不起返回 false 由 UI 降级。
class Launcher {
  const Launcher();

  /// 外部打开一个 URI 字符串。畸形串或无 app 处理 → false（不抛）。
  Future<bool> open(String raw) async {
    final uri = Uri.tryParse(raw);
    if (uri == null) return false;
    try {
      if (!await canLaunchUrl(uri)) return false;
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<bool> dial(String number) => open('tel:$number');
  Future<bool> email(String address) => open('mailto:$address');
}
