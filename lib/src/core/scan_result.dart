/// 一次扫码识别出的结构化结果。密封类：`switch` 全覆盖，UI 按类型给动作。
sealed class ScanResult {
  /// 扫到的原始字符串，始终原样保留（非拉丁、超长数字都不改写）。
  final String raw;
  const ScanResult(this.raw);
}

/// http/https 网址。
class UrlResult extends ScanResult {
  const UrlResult(super.raw);
}

/// 非 http 的自定义 scheme（如 steam://、mailto 以外的 app 深链）。
class AppLinkResult extends ScanResult {
  final String scheme; // 小写，不含冒号，如 "steam"
  const AppLinkResult(super.raw, this.scheme);
}

/// WIFI:S:…;T:…;P:…; 名片。字段全部为已解码字符串。
class WifiResult extends ScanResult {
  final String ssid;
  final String password;
  final String security; // "WPA" | "WEP" | "nopass"
  final bool hidden;
  const WifiResult(
    super.raw, {
    required this.ssid,
    required this.password,
    required this.security,
    required this.hidden,
  });
}

/// tel: 电话。
class TelResult extends ScanResult {
  final String number;
  const TelResult(super.raw, this.number);
}

/// mailto: 邮箱。
class EmailResult extends ScanResult {
  final String address;
  const EmailResult(super.raw, this.address);
}

/// geo: 坐标。
class GeoResult extends ScanResult {
  const GeoResult(super.raw);
}

/// 兜底纯文本；若内部含网址，`embeddedUrl` 给出第一个可打开的链接。
class TextResult extends ScanResult {
  final String? embeddedUrl;
  const TextResult(super.raw, {this.embeddedUrl});
}

/// 把原始扫码字符串判类型。纯函数、无副作用、绝不抛异常。
class ScanResultParser {
  const ScanResultParser();

  static final _embeddedUrl = RegExp(r'https?://[^\s]+', caseSensitive: false);
  static final _scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*):');

  ScanResult parse(String raw) {
    final lower = raw.toLowerCase();

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return UrlResult(raw);
    }
    if (lower.startsWith('wifi:')) {
      return _parseWifi(raw);
    }
    if (lower.startsWith('tel:')) {
      return TelResult(raw, raw.substring(4));
    }
    if (lower.startsWith('mailto:')) {
      return EmailResult(raw, raw.substring(7));
    }
    if (lower.startsWith('geo:')) {
      return GeoResult(raw);
    }

    final m = _scheme.firstMatch(raw);
    if (m != null) {
      return AppLinkResult(raw, m.group(1)!.toLowerCase());
    }

    final e = _embeddedUrl.firstMatch(raw);
    return TextResult(raw, embeddedUrl: e?.group(0));
  }

  WifiResult _parseWifi(String raw) {
    final body = raw.substring('WIFI:'.length);
    String ssid = '', password = '', security = 'nopass';
    bool hidden = false;

    final buf = StringBuffer();
    final fields = <String>[];
    for (int i = 0; i < body.length; i++) {
      final c = body[i];
      if (c == r'\' && i + 1 < body.length) {
        buf.write(body[i + 1]);
        i++;
      } else if (c == ';') {
        fields.add(buf.toString());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    if (buf.isNotEmpty) fields.add(buf.toString());

    for (final f in fields) {
      if (f.length < 2 || f[1] != ':') continue;
      final key = f[0].toUpperCase();
      final value = f.substring(2);
      switch (key) {
        case 'S':
          ssid = value;
        case 'P':
          password = value;
        case 'T':
          security = value.isEmpty ? 'nopass' : value;
        case 'H':
          hidden = value.toLowerCase() == 'true';
      }
    }
    return WifiResult(raw,
        ssid: ssid, password: password, security: security, hidden: hidden);
  }
}
