import 'scan_result.dart';

/// 一条历史记录：原始内容 + 类型短标签 + 扫码时间。
class HistoryEntry {
  final String content;
  final String type;
  final DateTime timestamp;

  const HistoryEntry({
    required this.content,
    required this.type,
    required this.timestamp,
  });

  factory HistoryEntry.fromScan(ScanResult r, DateTime timestamp) =>
      HistoryEntry(content: r.raw, type: kindOf(r), timestamp: timestamp);

  static String kindOf(ScanResult r) => switch (r) {
        UrlResult() => 'url',
        AppLinkResult() => 'applink',
        WifiResult() => 'wifi',
        TelResult() => 'tel',
        EmailResult() => 'email',
        GeoResult() => 'geo',
        FidoResult() => 'fido',
        TextResult() => 'text',
      };

  Map<String, dynamic> toJson() => {
        'content': content,
        'type': type,
        'ts': timestamp.toIso8601String(),
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        content: j['content'] as String,
        type: j['type'] as String,
        timestamp: DateTime.parse(j['ts'] as String),
      );
}
