import 'package:flutter_test/flutter_test.dart';
import 'package:saole/src/core/url_display.dart';

void main() {
  test('常规 https URL 拆出 host 三段', () {
    final p = splitUrlForDisplay('https://example.com/path?q=1');
    expect(p, isNotNull);
    expect(p!.prefix, 'https://');
    expect(p.host, 'example.com');
    expect(p.suffix, '/path?q=1');
  });

  test('无路径时 suffix 为空', () {
    final p = splitUrlForDisplay('http://example.com');
    expect(p!.prefix, 'http://');
    expect(p.host, 'example.com');
    expect(p.suffix, '');
  });

  test('host 大小写保留原样', () {
    final p = splitUrlForDisplay('https://ExAmple.COM/x');
    expect(p!.host, 'ExAmple.COM');
    expect(p.suffix, '/x');
  });

  test('路径里再次出现域名不干扰（取第一次）', () {
    final p = splitUrlForDisplay('https://example.com/https://example.com');
    expect(p!.prefix, 'https://');
    expect(p.host, 'example.com');
    expect(p.suffix, '/https://example.com');
  });

  test('带端口', () {
    final p = splitUrlForDisplay('https://example.com:8443/a');
    expect(p!.host, 'example.com');
    expect(p.suffix, ':8443/a');
  });

  test('非 http(s) 返回 null', () {
    expect(splitUrlForDisplay('steam://run/123'), isNull);
    expect(splitUrlForDisplay('mailto:a@b.com'), isNull);
  });

  test('畸形串返回 null，不抛', () {
    expect(splitUrlForDisplay('https://'), isNull);
    expect(splitUrlForDisplay('http:// spaces bad'), isNull);
    expect(splitUrlForDisplay(''), isNull);
  });
}
