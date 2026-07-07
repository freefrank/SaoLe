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
    test('KEY:VALUE 无 :// 归 Text（SN:00123456）', () {
      expect(p.parse('SN:00123456'), isA<TextResult>());
    });
    test('危险 scheme 无 :// 归 Text（javascript:）', () {
      expect(p.parse('javascript:alert(1)'), isA<TextResult>());
    });
    test('magnet:/bitcoin: 无 :// 归 Text', () {
      expect(p.parse('magnet:?xt=urn:btih:abc'), isA<TextResult>());
      expect(p.parse('bitcoin:1AaddrX'), isA<TextResult>());
    });
    test('含 :// 的 scheme 仍是 AppLink', () {
      final r = p.parse('steam://run/570');
      expect(r, isA<AppLinkResult>());
      expect((r as AppLinkResult).scheme, 'steam');
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
    test('security 归一化 T:wpa → WPA', () {
      final r = p.parse('WIFI:S:N;T:wpa;P:x;;') as WifiResult;
      expect(r.security, 'WPA');
    });
    test('H 字段缺失 → hidden false', () {
      final r = p.parse('WIFI:S:N;T:WPA;P:x;;') as WifiResult;
      expect(r.hidden, false);
    });
    test('小写前缀+小写键也解析', () {
      final r = p.parse('wifi:s:Net;t:wpa;;') as WifiResult;
      expect(r.ssid, 'Net');
      expect(r.security, 'WPA');
    });
    test('值内裸冒号保留', () {
      final r = p.parse('WIFI:S:N;T:WPA;P:a:b;;') as WifiResult;
      expect(r.password, 'a:b');
    });
    test('末尾孤立反斜杠不崩', () {
      expect(() => p.parse(r'WIFI:S:a\'), returnsNormally);
    });
  });

  group('parse 绝不抛异常', () {
    for (final x in [r'\', r'WIFI:\', ':::', 'a:', '://', '   ']) {
      test('输入 ${x.isEmpty ? '(empty)' : x}', () {
        expect(() => p.parse(x), returnsNormally);
      });
    }
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

  group('FIDO', () {
    test('FIDO:/ 单斜杠识别为 FidoResult', () {
      expect(p.parse('FIDO:/1234ABCD'), isA<FidoResult>());
    });
    test('大小写不敏感', () {
      expect(p.parse('fido:/xyz'), isA<FidoResult>());
    });
    test('raw 原样保留', () {
      expect(p.parse('FIDO:/abc').raw, 'FIDO:/abc');
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
    test('中文括号包裹的网址→strip 尾部标点', () {
      final r = p.parse('看（https://ex.com/x）好') as TextResult;
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
