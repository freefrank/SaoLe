import 'package:flutter_test/flutter_test.dart';
import 'package:saole/src/core/scan_result.dart';

void main() {
  final p = ScanResultParser();

  group('URL', () {
    test('http 识别为 UrlResult', () {
      expect(p.parse('http://example.com'), isA<UrlResult>());
    });
    test('https 识别为 UrlResult', () {
      final r = p.parse('https://a.b/c?d=1');
      expect(r, isA<UrlResult>());
      expect(r.raw, 'https://a.b/c?d=1');
    });
    test('大小写混合 scheme 也识别', () {
      expect(p.parse('HTTPS://EXAMPLE.COM'), isA<UrlResult>());
    });
  });

  group('AppLink', () {
    test('steam:// 识别为 AppLink，scheme 小写', () {
      final r = p.parse('steam://run/570');
      expect(r, isA<AppLinkResult>());
      expect((r as AppLinkResult).scheme, 'steam');
    });
    test('超长 uint64（Steam client_id）不溢出、原样保留', () {
      const raw = 'steam://joinlobby/570/76561199999999999/76561199888888888';
      final r = p.parse(raw);
      expect(r, isA<AppLinkResult>());
      expect(r.raw, raw);
    });
  });

  group('WiFi', () {
    test('标准串解析全字段', () {
      final r = p.parse('WIFI:S:MyNet;T:WPA;P:secret123;H:false;;');
      expect(r, isA<WifiResult>());
      r as WifiResult;
      expect(r.ssid, 'MyNet');
      expect(r.password, 'secret123');
      expect(r.security, 'WPA');
      expect(r.hidden, false);
    });
    test('字段乱序也能解析', () {
      final r = p.parse('WIFI:T:WEP;P:pw;S:Net;;') as WifiResult;
      expect(r.ssid, 'Net');
      expect(r.security, 'WEP');
    });
    test('nopass 开放网络', () {
      final r = p.parse('WIFI:S:Open;T:nopass;;') as WifiResult;
      expect(r.security, 'nopass');
      expect(r.password, '');
    });
    test('转义分号/冒号/反斜杠还原', () {
      final r = p.parse(r'WIFI:S:My\;Net;T:WPA;P:a\:b\\c;;') as WifiResult;
      expect(r.ssid, 'My;Net');
      expect(r.password, r'a:b\c');
    });
    test('隐藏网络 H:true', () {
      final r = p.parse('WIFI:S:H;T:WPA;P:x;H:true;;') as WifiResult;
      expect(r.hidden, true);
    });
    test('畸形串（缺 SSID）不崩，ssid 为空', () {
      final r = p.parse('WIFI:T:WPA;;');
      expect(r, isA<WifiResult>());
      expect((r as WifiResult).ssid, '');
    });
    test('残缺 WIFI: 前缀无内容不崩', () {
      expect(() => p.parse('WIFI:'), returnsNormally);
      expect(p.parse('WIFI:'), isA<WifiResult>());
    });
  });

  group('scheme 短链', () {
    test('tel:', () {
      final r = p.parse('tel:+8613800138000') as TelResult;
      expect(r.number, '+8613800138000');
    });
    test('mailto:', () {
      final r = p.parse('mailto:a@b.com') as EmailResult;
      expect(r.address, 'a@b.com');
    });
    test('geo:', () {
      expect(p.parse('geo:39.9,116.4'), isA<GeoResult>());
    });
  });

  group('Text 兜底', () {
    test('纯文本', () {
      final r = p.parse('just some text') as TextResult;
      expect(r.embeddedUrl, isNull);
    });
    test('非拉丁文本原样保留', () {
      const raw = '扫了一下就连上了 📶';
      final r = p.parse(raw) as TextResult;
      expect(r.raw, raw);
    });
    test('文本内含网址→提取 embeddedUrl', () {
      final r = p.parse('看这里 https://ex.com/x 谢谢') as TextResult;
      expect(r.embeddedUrl, 'https://ex.com/x');
    });
    test('空串不崩', () {
      expect(() => p.parse(''), returnsNormally);
      expect(p.parse(''), isA<TextResult>());
    });
    test('纯空白视为文本', () {
      expect(p.parse('   '), isA<TextResult>());
    });
  });
}
