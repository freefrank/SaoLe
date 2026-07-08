import 'package:flutter_test/flutter_test.dart';
import 'package:saole/src/core/history_entry.dart';
import 'package:saole/src/core/scan_result.dart';

void main() {
  test('fromScan 记录 content/type/timestamp', () {
    final ts = DateTime.utc(2026, 7, 7, 12);
    final e = HistoryEntry.fromScan(const UrlResult('https://x.com'), ts);
    expect(e.content, 'https://x.com');
    expect(e.type, 'url');
    expect(e.timestamp, ts);
  });

  test('JSON 往返保真（含非拉丁）', () {
    final e = HistoryEntry(
      content: '扫了 https://x',
      type: 'text',
      timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
    );
    final back = HistoryEntry.fromJson(e.toJson());
    expect(back.content, e.content);
    expect(back.type, e.type);
    expect(back.timestamp, e.timestamp);
  });

  test('wifi 类型标签', () {
    final e = HistoryEntry.fromScan(
      const WifiResult(
        'WIFI:S:N;;',
        ssid: 'N',
        password: '',
        security: 'nopass',
        hidden: false,
      ),
      DateTime.utc(2026),
    );
    expect(e.type, 'wifi');
  });

  test('fido 类型标签', () {
    final e = HistoryEntry.fromScan(
      const FidoResult('FIDO:/abc'),
      DateTime.utc(2026),
    );
    expect(e.type, 'fido');
  });
}
