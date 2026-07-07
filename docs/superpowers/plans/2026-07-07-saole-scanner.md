# 扫了 (SaoLe) 极速扫码器 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 Android 极简极速扫码器：开摄像头识别二维码/条码 → 判类型 → 结果面板给动作（打开 URL / 连 WiFi / 拨号等），带历史、设置、桌面小组件与快捷磁贴快速入口。

**Architecture:** 三层：`core/`（纯 Dart 零 Flutter 依赖、可单测的解析与模型）→ `services/`（`ChangeNotifier` 状态 + 平台封装）→ `ui/`（Flutter 界面）。状态管理用 `provider`（不用 riverpod，冷启动更快）。Android 原生集成（磁贴/小组件/WiFi 连接）纯原生实现，无额外 pub 依赖。核心业务逻辑（`ScanResultParser`）是唯一有分量的纯函数，重点单测对象。

**Tech Stack:** Flutter 3.44.x / Dart ^3.12.2 · `mobile_scanner` ^7.2.0 · `provider` ^6.1.2 · `path_provider` · `shared_preferences` · `url_launcher` · `share_plus` · `image_picker` · Kotlin platform channel（WiFi）· 原生 AppWidget + TileService。

**平台目标：Android 12+（`minSdk = 31`，`targetSdk = 34`）。** 只支持 Android 12 以上大幅简化原生代码：WiFi 一律走 API 30+ 的 `ACTION_WIFI_ADD_NETWORKS` 面板（无需定位权限、无 <30 回退分支）；无需为老 API 做兼容降级。

**速度优先（本项目最高优先级）：** 卖点是冷启动快、识别跟手、壳子薄。硬约束——
- 不引入 riverpod（用 provider，更轻）；不引入任何广告/埋点/分析 SDK。
- `main()` 里 `HistoryStore` 与 `SettingsStore` 的加载**并行**（`Future.wait`），不串行 await。
- `mobile_scanner` 用 **bundled ML Kit 模型**（默认），冷启动即可识别，不走首扫下载。
- release 构建开 R8 收缩 + 资源压缩（`isMinifyEnabled = true` / `isShrinkResources = true`），减小包体、加快加载。
- **NDK：** 当前纯 Flutter + native ML Kit（mobile_scanner 内部已是 C++/ML Kit）已足够快，MVP **不自写 NDK**；仅当后续实测识别或解码成为瓶颈时才考虑（属 v2 优化，不阻塞 MVP）。

**参考来源（只读，不改）：** AVA 工程 `/mnt/c/Users/freefrank/ownCloud/Git/AnotherVaporAuth/app/`。借用其 `responsive.dart`（`context.r()`，Task 1）、签名配置模板（Task 13）与 CI 门禁（Task 14）；`theme.dart` 深度依赖 riverpod/skins，本项目**精简改写**为 dark/light 双变体（Task 3），不照搬。设计文档列出的 `scanline_overlay`（CRT 扫描线动效）深度绑定 riverpod + skins + route_observer，纯装饰，**MVP 不实现**（不为一个装饰引入 riverpod，违背薄壳/冷启动定位），v2 若需要再以无依赖方式重写。业务代码全部全新编写。

---

## File Structure

```
lib/
  main.dart                     入口：读 scan_only intent extra，装配 provider，MaterialApp
  src/
    app/
      theme.dart                精简 SaoTokens（dark/light 双变体）+ buildSaoTheme
      responsive.dart           从 AVA 照搬（context.r()），去 riverpod
    core/
      scan_result.dart          ScanResult 密封类族 + ScanResultParser（纯函数，重点单测）
      history_entry.dart        HistoryEntry 模型 + JSON 序列化
    services/
      history_store.dart        ChangeNotifier + path_provider JSON 持久化
      settings_store.dart       ChangeNotifier + shared_preferences
      platform/
        launcher.dart           url_launcher 封装（URL/App 链接直开 + 唤起探测）
        wifi_connect.dart        WiFi platform channel（Dart 侧）
    ui/
      home_shell.dart           普通启动首屏：扫码 + 底部历史/设置入口
      scanner_screen.dart       MobileScanner + 手电筒/相册 + _done 闩锁；支持 scanOnly
      result_sheet.dart         按 ScanResult 类型给动作的底部面板
      history_screen.dart       历史列表（倒序、复现、滑删、清空）
      settings_screen.dart      设置开关
android/app/src/main/
  kotlin/pro/dotslash/saole/
    MainActivity.kt             读 mode extra；注册 WiFi MethodChannel
    ScanTileService.kt          Quick Settings 磁贴 → 启动 scan_only
    ScanWidgetProvider.kt       桌面小组件 → PendingIntent 启动 scan_only
  res/layout/scan_widget.xml    小组件布局（单个点击开扫图标块）
  res/xml/scan_widget_info.xml  AppWidget 元数据
  AndroidManifest.xml           相机权限/feature、磁贴、小组件、queries 注册
test/
  core/scan_result_parser_test.dart   全类型 + 畸形串 + 超长 uint64 + 非拉丁
  core/history_entry_test.dart        JSON 往返
  services/history_store_test.dart    读写往返 + 损坏文件恢复
  services/wifi_connect_test.dart     platform channel mock 验参
```

---

## Task 0: 项目骨架与依赖

**Files:**
- Modify: `pubspec.yaml`
- Delete demo: `lib/main.dart`（整体重写，见 Task 12）
- Delete: `test/widget_test.dart`（counter demo 测试，无效）

- [ ] **Step 1: 重写 pubspec.yaml 依赖块**

将 `dependencies:` / `dev_dependencies:` 段替换为：

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # 扫码核心
  mobile_scanner: ^7.2.0
  # 状态管理（轻量，冷启动快；不用 riverpod）
  provider: ^6.1.2
  # 历史 JSON 落盘目录
  path_provider: ^2.1.5
  # 设置持久化
  shared_preferences: ^2.3.3
  # URL / App 链接直开
  url_launcher: ^6.3.2
  # 结果分享
  share_plus: ^10.1.4
  # 相册选图识别
  image_picker: ^1.1.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
```

- [ ] **Step 2: 删除 counter demo 测试**

Run: `rm test/widget_test.dart`

- [ ] **Step 3: 拉取依赖**

Run: `flutter pub get`
Expected: `Got dependencies!`，无版本冲突报错。

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git rm test/widget_test.dart
git commit -m "chore: add scanner deps, drop counter demo test"
```

---

## Task 1: 借用 responsive.dart

**Files:**
- Create: `lib/src/app/responsive.dart`

- [ ] **Step 1: 照搬 AVA responsive.dart（无 riverpod 依赖，可直接用）**

内容与 `/mnt/c/Users/freefrank/ownCloud/Git/AnotherVaporAuth/app/lib/src/app/responsive.dart` 完全一致（`ResponsiveContext` 扩展，提供 `context.scale` / `context.r(v)` / `context.rInsets(...)`）。直接复制该文件到 `lib/src/app/responsive.dart`。

Run: `cp /mnt/c/Users/freefrank/ownCloud/Git/AnotherVaporAuth/app/lib/src/app/responsive.dart lib/src/app/responsive.dart`

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze lib/src/app/responsive.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/src/app/responsive.dart
git commit -m "feat: borrow responsive sizing helper from AVA"
```

---

## Task 2: 核心解析 ScanResult + ScanResultParser（TDD，项目核心）

**Files:**
- Create: `lib/src/core/scan_result.dart`
- Test: `test/core/scan_result_parser_test.dart`

这是全 app 唯一有分量的业务逻辑，纯函数、零 Flutter 依赖、重点单测对象。健壮性要求：畸形 WiFi 串不崩、超长 uint64（Steam client_id 那类）不溢出（**全程保持字符串，绝不 `int.parse`**）、非拉丁文本原样保留、空串不崩。

- [ ] **Step 1: 定义 ScanResult 密封类族（先立类型，测试才能引用）**

写 `lib/src/core/scan_result.dart` 顶部的类型定义（parser 下一步补）：

```dart
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
```

- [ ] **Step 2: 写解析器测试（红）**

写 `test/core/scan_result_parser_test.dart`：

```dart
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
      expect(r.raw, raw); // 全程字符串，无 int.parse
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
```

- [ ] **Step 3: 运行测试确认失败**

Run: `flutter test test/core/scan_result_parser_test.dart`
Expected: 编译失败 —— `ScanResultParser` 未定义。

- [ ] **Step 4: 实现 ScanResultParser（绿）**

追加到 `lib/src/core/scan_result.dart` 末尾：

```dart
/// 把原始扫码字符串判类型。纯函数、无副作用、绝不抛异常。
class ScanResultParser {
  const ScanResultParser();

  // 文本中提取第一个 http(s) 链接。
  static final _embeddedUrl = RegExp(r'https?://[^\s]+', caseSensitive: false);
  // 通用 URI scheme 头：字母开头 + 字母/数字/+-. ，后跟冒号。
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

    // 其它自定义 scheme（steam://、bitcoin: 等）→ AppLink。
    final m = _scheme.firstMatch(raw);
    if (m != null) {
      return AppLinkResult(raw, m.group(1)!.toLowerCase());
    }

    // 兜底文本；含网址就顺手提取。
    final e = _embeddedUrl.firstMatch(raw);
    return TextResult(raw, embeddedUrl: e?.group(0));
  }

  // WIFI:S:…;T:…;P:…;H:…;; —— 字段顺序不固定，值可转义 \; \, \: \\ 。
  WifiResult _parseWifi(String raw) {
    final body = raw.substring('WIFI:'.length);
    String ssid = '', password = '', security = 'nopass';
    bool hidden = false;

    // 逐字符扫描：遇未转义分号切分一个字段。
    final buf = StringBuffer();
    final fields = <String>[];
    for (int i = 0; i < body.length; i++) {
      final c = body[i];
      if (c == r'\' && i + 1 < body.length) {
        buf.write(body[i + 1]); // 保留被转义的原字符
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
      if (f.length < 2 || f[1] != ':') continue; // 需形如 X:value
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
```

- [ ] **Step 5: 运行测试确认全绿**

Run: `flutter test test/core/scan_result_parser_test.dart`
Expected: All tests passed!

- [ ] **Step 6: Commit**

```bash
git add lib/src/core/scan_result.dart test/core/scan_result_parser_test.dart
git commit -m "feat(core): ScanResult sealed types + robust parser with tests"
```

---

## Task 3: 精简主题 SaoTokens

**Files:**
- Create: `lib/src/app/theme.dart`

- [ ] **Step 1: 编写精简双变体主题（去 riverpod/skins）**

```dart
import 'package:flutter/material.dart';

/// 明暗两个变体。SaoLe 不做花哨皮肤，只保留干净的 dark/light。
enum SaoBrightness { system, dark, light }

Brightness resolveBrightness(SaoBrightness mode, Brightness platform) {
  switch (mode) {
    case SaoBrightness.light:
      return Brightness.light;
    case SaoBrightness.dark:
      return Brightness.dark;
    case SaoBrightness.system:
      return platform;
  }
}

/// 挂在 [ThemeData] 上的设计令牌，任意 widget 可读当前调色板。
@immutable
class SaoTokens extends ThemeExtension<SaoTokens> {
  final Brightness brightness;
  final Color bg;
  final Color panel;
  final Color line;
  final Color text;
  final Color muted;
  final Color accent;
  final Color good;
  final Color bad;
  final double radius;

  const SaoTokens({
    required this.brightness,
    required this.bg,
    required this.panel,
    required this.line,
    required this.text,
    required this.muted,
    required this.accent,
    required this.good,
    required this.bad,
    required this.radius,
  });

  static const dark = SaoTokens(
    brightness: Brightness.dark,
    bg: Color(0xFF0F1115),
    panel: Color(0xFF161A20),
    line: Color(0xFF2A303B),
    text: Color(0xFFE7EAF0),
    muted: Color(0xFF8B93A2),
    accent: Color(0xFF5B8CFF),
    good: Color(0xFF34C77B),
    bad: Color(0xFFEF4E5E),
    radius: 14,
  );

  static const light = SaoTokens(
    brightness: Brightness.light,
    bg: Color(0xFFF4F6F9),
    panel: Color(0xFFFFFFFF),
    line: Color(0xFFE2E6EC),
    text: Color(0xFF1B2026),
    muted: Color(0xFF64707F),
    accent: Color(0xFF2F6BFF),
    good: Color(0xFF15803D),
    bad: Color(0xFFDC2626),
    radius: 14,
  );

  static SaoTokens of(Brightness b) =>
      b == Brightness.light ? light : dark;

  @override
  SaoTokens copyWith() => this;

  @override
  SaoTokens lerp(ThemeExtension<SaoTokens>? other, double t) {
    if (other is! SaoTokens) return this;
    return t < 0.5 ? this : other;
  }
}

/// 读令牌的便捷扩展：`context.tokens`。
extension SaoThemeContext on BuildContext {
  SaoTokens get tokens => Theme.of(this).extension<SaoTokens>()!;
}

ThemeData buildSaoTheme(Brightness brightness) {
  final t = SaoTokens.of(brightness);
  final scheme = ColorScheme.fromSeed(
    seedColor: t.accent,
    brightness: brightness,
  ).copyWith(primary: t.accent, error: t.bad, surface: t.panel);

  final base = ThemeData(useMaterial3: true, brightness: brightness);
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    extensions: [t],
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.text,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: t.panel,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(t.radius),
        side: BorderSide(color: t.line),
      ),
    ),
    listTileTheme: ListTileThemeData(textColor: t.text, iconColor: t.muted),
    dividerColor: t.line,
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: t.panel,
      contentTextStyle: TextStyle(color: t.text),
    ),
  );
}
```

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze lib/src/app/theme.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/src/app/theme.dart
git commit -m "feat: slim dark/light theme tokens (no riverpod)"
```

---

## Task 4: HistoryEntry 模型（TDD）

**Files:**
- Create: `lib/src/core/history_entry.dart`
- Test: `test/core/history_entry_test.dart`

- [ ] **Step 1: 写测试（红）**

写 `test/core/history_entry_test.dart`：

```dart
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
      const WifiResult('WIFI:S:N;;',
          ssid: 'N', password: '', security: 'nopass', hidden: false),
      DateTime.utc(2026),
    );
    expect(e.type, 'wifi');
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/history_entry_test.dart`
Expected: 编译失败 —— `HistoryEntry` 未定义。

- [ ] **Step 3: 实现**

写 `lib/src/core/history_entry.dart`：

```dart
import 'scan_result.dart';

/// 一条历史记录：原始内容 + 类型短标签 + 扫码时间。
class HistoryEntry {
  final String content;
  final String type; // 'url' | 'applink' | 'wifi' | 'tel' | 'email' | 'geo' | 'text'
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
```

- [ ] **Step 4: 运行确认全绿**

Run: `flutter test test/core/history_entry_test.dart`
Expected: All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/src/core/history_entry.dart test/core/history_entry_test.dart
git commit -m "feat(core): HistoryEntry model with JSON round-trip"
```

---

## Task 5: HistoryStore 持久化（TDD，含损坏文件恢复）

**Files:**
- Create: `lib/src/services/history_store.dart`
- Test: `test/services/history_store_test.dart`

- [ ] **Step 1: 写测试（红）**

写 `test/services/history_store_test.dart`：

```dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:saole/src/core/history_entry.dart';
import 'package:saole/src/services/history_store.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('saole_hist');
    file = File('${tmp.path}/history.json');
  });
  tearDown(() async => tmp.delete(recursive: true));

  HistoryEntry entry(String c) =>
      HistoryEntry(content: c, type: 'text', timestamp: DateTime.utc(2026));

  test('add 后 load 往返，倒序（最新在前）', () async {
    final s = HistoryStore(file: file);
    await s.load();
    await s.add(entry('first'));
    await s.add(entry('second'));
    expect(s.entries.map((e) => e.content).toList(), ['second', 'first']);

    final reloaded = HistoryStore(file: file);
    await reloaded.load();
    expect(reloaded.entries.first.content, 'second');
  });

  test('损坏文件优雅恢复为空历史，不抛', () async {
    await file.writeAsString('{ this is not json ][');
    final s = HistoryStore(file: file);
    await expectLater(s.load(), completes);
    expect(s.entries, isEmpty);
  });

  test('文件不存在时 load 为空', () async {
    final s = HistoryStore(file: file);
    await s.load();
    expect(s.entries, isEmpty);
  });

  test('removeAt 与 clear', () async {
    final s = HistoryStore(file: file);
    await s.load();
    await s.add(entry('a'));
    await s.add(entry('b'));
    await s.removeAt(0); // 删最新 'b'
    expect(s.entries.single.content, 'a');
    await s.clear();
    expect(s.entries, isEmpty);
  });

  test('notifyListeners 在变更时触发', () async {
    final s = HistoryStore(file: file);
    await s.load();
    var n = 0;
    s.addListener(() => n++);
    await s.add(entry('x'));
    expect(n, greaterThan(0));
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/history_store_test.dart`
Expected: 编译失败 —— `HistoryStore` 未定义。

- [ ] **Step 3: 实现**

写 `lib/src/services/history_store.dart`：

```dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/history_entry.dart';

/// 历史记录存储：内存列表 + JSON 文件落盘。倒序（最新在前）。
/// 损坏文件读取时优雅退化为空历史，绝不崩。
class HistoryStore extends ChangeNotifier {
  final File file;
  final List<HistoryEntry> _entries = [];

  HistoryStore({required this.file});

  /// 生产环境用 app 文档目录下的 history.json。
  static Future<HistoryStore> forApp() async {
    final dir = await getApplicationDocumentsDirectory();
    final store = HistoryStore(file: File('${dir.path}/history.json'));
    await store.load();
    return store;
  }

  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  Future<void> load() async {
    _entries.clear();
    try {
      if (!await file.exists()) return;
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      for (final j in list) {
        _entries.add(HistoryEntry.fromJson(j as Map<String, dynamic>));
      }
    } catch (_) {
      // 损坏/半写文件：丢弃，从空开始，不打扰用户。
      _entries.clear();
    }
    notifyListeners();
  }

  Future<void> add(HistoryEntry e) async {
    _entries.insert(0, e);
    await _flush();
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _entries.length) return;
    _entries.removeAt(index);
    await _flush();
    notifyListeners();
  }

  Future<void> clear() async {
    _entries.clear();
    await _flush();
    notifyListeners();
  }

  Future<void> _flush() async {
    final data = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await file.writeAsString(data);
  }
}
```

- [ ] **Step 4: 运行确认全绿**

Run: `flutter test test/services/history_store_test.dart`
Expected: All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/history_store.dart test/services/history_store_test.dart
git commit -m "feat(services): HistoryStore JSON persistence with corrupt-file recovery"
```

---

## Task 6: SettingsStore（shared_preferences）

**Files:**
- Create: `lib/src/services/settings_store.dart`

设计文档的设置项：扫到即自动打开（默认**关**，防钓鱼）、震动反馈、提示音、记录历史、连续扫描模式。外加主题亮度偏好（Task 3 的 `SaoBrightness`）。

- [ ] **Step 1: 实现**

写 `lib/src/services/settings_store.dart`：

```dart
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';

/// 用户设置：内存缓存 + shared_preferences 持久化，改动即写盘并通知。
class SettingsStore extends ChangeNotifier {
  final SharedPreferences _prefs;
  SettingsStore(this._prefs);

  static Future<SettingsStore> forApp() async =>
      SettingsStore(await SharedPreferences.getInstance());

  // key 常量
  static const _kAutoOpen = 'auto_open';
  static const _kHaptics = 'haptics';
  static const _kBeep = 'beep';
  static const _kKeepHistory = 'keep_history';
  static const _kContinuous = 'continuous';
  static const _kBrightness = 'brightness';

  /// 扫到 URL/AppLink 即自动打开（默认关，防钓鱼）。
  bool get autoOpen => _prefs.getBool(_kAutoOpen) ?? false;
  set autoOpen(bool v) => _set(_kAutoOpen, v);

  bool get haptics => _prefs.getBool(_kHaptics) ?? true;
  set haptics(bool v) => _set(_kHaptics, v);

  bool get beep => _prefs.getBool(_kBeep) ?? false;
  set beep(bool v) => _set(_kBeep, v);

  bool get keepHistory => _prefs.getBool(_kKeepHistory) ?? true;
  set keepHistory(bool v) => _set(_kKeepHistory, v);

  bool get continuous => _prefs.getBool(_kContinuous) ?? false;
  set continuous(bool v) => _set(_kContinuous, v);

  SaoBrightness get brightness =>
      SaoBrightness.values[_prefs.getInt(_kBrightness) ?? 0];
  set brightness(SaoBrightness v) {
    _prefs.setInt(_kBrightness, v.index);
    notifyListeners();
  }

  void _set(String key, bool v) {
    _prefs.setBool(key, v);
    notifyListeners();
  }
}
```

- [ ] **Step 2: 验证 analyze**

Run: `flutter analyze lib/src/services/settings_store.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/src/services/settings_store.dart
git commit -m "feat(services): SettingsStore over shared_preferences"
```

---

## Task 7: launcher 封装（url_launcher）

**Files:**
- Create: `lib/src/services/platform/launcher.dart`

- [ ] **Step 1: 实现**

写 `lib/src/services/platform/launcher.dart`：

```dart
import 'package:url_launcher/url_launcher.dart';

/// url_launcher 的薄封装：打开 URL / App 链接，唤不起返回 false 由 UI 降级。
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

  /// 拨号 tel:。
  Future<bool> dial(String number) => open('tel:$number');

  /// 写邮件 mailto:。
  Future<bool> email(String address) => open('mailto:$address');
}
```

- [ ] **Step 2: 验证 analyze**

Run: `flutter analyze lib/src/services/platform/launcher.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/src/services/platform/launcher.dart
git commit -m "feat(platform): url_launcher wrapper"
```

---

## Task 8: wifi_connect platform channel（Dart 侧 + mock 测试）

**Files:**
- Create: `lib/src/services/platform/wifi_connect.dart`
- Test: `test/services/wifi_connect_test.dart`

Dart 侧只负责把参数打包发到 `saole/wifi` channel；真正连接逻辑在 Kotlin（Task 9）。

- [ ] **Step 1: 写 mock 测试（红）**

写 `test/services/wifi_connect_test.dart`：

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saole/src/services/platform/wifi_connect.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('saole/wifi');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  test('connect 把 ssid/password/security/hidden 传给原生', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async {
      received = call;
      return true;
    });

    final ok = await const WifiConnect().connect(
      ssid: 'Net',
      password: 'pw',
      security: 'WPA',
      hidden: false,
    );

    expect(ok, true);
    expect(received?.method, 'connect');
    expect(received?.arguments, {
      'ssid': 'Net',
      'password': 'pw',
      'security': 'WPA',
      'hidden': false,
    });

    messenger.setMockMethodCallHandler(channel, null);
  });

  test('原生抛 PlatformException 时返回 false，不抛', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'ERR');
    });
    final ok = await const WifiConnect()
        .connect(ssid: 'N', password: '', security: 'nopass', hidden: false);
    expect(ok, false);
    messenger.setMockMethodCallHandler(channel, null);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/services/wifi_connect_test.dart`
Expected: 编译失败 —— `WifiConnect` 未定义。

- [ ] **Step 3: 实现**

写 `lib/src/services/platform/wifi_connect.dart`：

```dart
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
```

- [ ] **Step 4: 运行确认全绿**

Run: `flutter test test/services/wifi_connect_test.dart`
Expected: All tests passed!

- [ ] **Step 5: Commit**

```bash
git add lib/src/services/platform/wifi_connect.dart test/services/wifi_connect_test.dart
git commit -m "feat(platform): WiFi connect channel (Dart side) with mock tests"
```

---

## Task 9: Android 原生集成（Manifest · MainActivity · 磁贴 · 小组件 · WiFi）

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml`
- Rewrite: `android/app/src/main/kotlin/pro/dotslash/saole/MainActivity.kt`
- Create: `android/app/src/main/kotlin/pro/dotslash/saole/ScanTileService.kt`
- Create: `android/app/src/main/kotlin/pro/dotslash/saole/ScanWidgetProvider.kt`
- Create: `android/app/src/main/res/layout/scan_widget.xml`
- Create: `android/app/src/main/res/xml/scan_widget_info.xml`
- Create: `android/app/src/main/res/drawable/ic_scan.xml`
- Modify: `android/app/build.gradle.kts`（applicationId/namespace → `pro.dotslash.saole`，minSdk 24）

无任何额外 pub 依赖。

- [ ] **Step 1: 改 build.gradle.kts 包名、minSdk 与 release 收缩**

在 `android/app/build.gradle.kts` 中：
- `namespace = "pro.dotslash.saole"`
- `applicationId = "pro.dotslash.saole"`
- `minSdk = 31`（Android 12+；简化 WiFi/磁贴原生逻辑，无需老 API 兼容）
- `targetSdk = 34`
- release buildType 内开启收缩（加快加载、减小包体）：
  ```kotlin
  release {
      isMinifyEnabled = true
      isShrinkResources = true
      // signingConfig 见 Task 13
  }
  ```
  （R8 收缩会移除 ML Kit 反射用到的类 → 保留 Task 9 已引入的 `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")`，并确保 `android/app/proguard-rules.pro` 存在，内容至少保留 mobile_scanner / ML Kit：`-keep class com.google.mlkit.** { *; }`。）

- [ ] **Step 2: 重写 AndroidManifest.xml**

写 `android/app/src/main/AndroidManifest.xml`：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- 扫码需要相机；相机非必需（可从相册识图），故 required=false 让无摄像头设备也能装 -->
    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera" android:required="false"/>

    <!-- url_launcher 在 Android 11+ 需声明要探测/唤起的 scheme -->
    <queries>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="http"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.DIAL"/>
            <data android:scheme="tel"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.SENDTO"/>
            <data android:scheme="mailto"/>
        </intent>
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="geo"/>
        </intent>
    </queries>

    <application
        android:label="扫了"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"/>
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- Quick Settings 磁贴：点击直接进 scan_only -->
        <service
            android:name=".ScanTileService"
            android:exported="true"
            android:icon="@drawable/ic_scan"
            android:label="扫了"
            android:permission="android.permission.BIND_QUICK_SETTINGS_TILE">
            <intent-filter>
                <action android:name="android.service.quicksettings.action.QS_TILE"/>
            </intent-filter>
        </service>

        <!-- 桌面小组件：点击直接进 scan_only -->
        <receiver
            android:name=".ScanWidgetProvider"
            android:exported="false">
            <intent-filter>
                <action android:name="android.appwidget.action.APPWIDGET_UPDATE"/>
            </intent-filter>
            <meta-data
                android:name="android.appwidget.provider"
                android:resource="@xml/scan_widget_info"/>
        </receiver>

        <meta-data
            android:name="flutterEmbedding"
            android:value="2"/>
    </application>
</manifest>
```

- [ ] **Step 3: 重写 MainActivity.kt（读 mode extra + WiFi channel）**

写 `android/app/src/main/kotlin/pro/dotslash/saole/MainActivity.kt`：

```kotlin
package pro.dotslash.saole

import android.content.Intent
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 磁贴/小组件复用已存在的 activity 时，新 intent 从这里进来。
    private var launchMode: String = "normal"

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        launchMode = intent.getStringExtra("mode") ?: "normal"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        launchMode = intent?.getStringExtra("mode") ?: "normal"
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, "saole/launch").setMethodCallHandler { call, result ->
            when (call.method) {
                "getMode" -> result.success(launchMode)
                else -> result.notImplemented()
            }
        }

        MethodChannel(messenger, "saole/wifi").setMethodCallHandler { call, result ->
            if (call.method == "connect") {
                result.success(
                    connectWifi(
                        call.argument<String>("ssid") ?: "",
                        call.argument<String>("password") ?: "",
                        call.argument<String>("security") ?: "nopass",
                        call.argument<Boolean>("hidden") ?: false,
                    )
                )
            } else {
                result.notImplemented()
            }
        }
    }

    // minSdk 31（Android 12+），API 30+ 的 ACTION_WIFI_ADD_NETWORKS 恒可用：
    // 拉起系统"添加网络"面板预填凭据（无需定位权限）。WEP 已弃用、
    // WifiNetworkSuggestion 不支持 → 回退到 WiFi 设置页（密码 Dart 侧已复制）。
    private fun connectWifi(
        ssid: String,
        password: String,
        security: String,
        hidden: Boolean,
    ): Boolean {
        return try {
            if (security.uppercase() == "WEP") {
                startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
                return true
            }
            val builder = WifiNetworkSuggestion.Builder().setSsid(ssid)
            if (hidden) builder.setIsHiddenSsid(true)
            if (security.uppercase() == "WPA") builder.setWpa2Passphrase(password)
            val suggestions = arrayListOf(builder.build())
            val addIntent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS).apply {
                putParcelableArrayListExtra(
                    Settings.EXTRA_WIFI_NETWORK_LIST, suggestions
                )
            }
            startActivity(addIntent)
            true
        } catch (e: Exception) {
            false
        }
    }
}
```

> `import android.os.Build` 在简化后已不再需要（TileService 的 API 34 分支仍需要它，保留其 import；MainActivity 若无其它 Build 用法可移除该 import，以 `flutter build` 的 lint 为准）。

- [ ] **Step 4: 写 ScanTileService.kt**

写 `android/app/src/main/kotlin/pro/dotslash/saole/ScanTileService.kt`：

```kotlin
package pro.dotslash.saole

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService

/// Quick Settings 磁贴：点击拉起 MainActivity 的 scan_only 模式。
class ScanTileService : TileService() {
    override fun onClick() {
        super.onClick()
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("mode", "scan_only")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val pi = PendingIntent.getActivity(
                this, 0, intent, PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pi)
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(intent)
        }
    }
}
```

- [ ] **Step 5: 写 ScanWidgetProvider.kt**

写 `android/app/src/main/kotlin/pro/dotslash/saole/ScanWidgetProvider.kt`：

```kotlin
package pro.dotslash.saole

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/// 桌面小组件：单个"点击开扫"图标块，点击拉起 scan_only。
/// 不回传数据，故纯原生 AppWidget，不引入 home_widget 包。
class ScanWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            val intent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("mode", "scan_only")
            }
            val pi = PendingIntent.getActivity(
                context, 0, intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
            val views = RemoteViews(context.packageName, R.layout.scan_widget).apply {
                setOnClickPendingIntent(R.id.widget_root, pi)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }
}
```

- [ ] **Step 6: 写小组件布局与元数据**

写 `android/app/src/main/res/drawable/ic_scan.xml`（简单扫码图标矢量）：

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="48dp" android:height="48dp"
    android:viewportWidth="24" android:viewportHeight="24"
    android:tint="#FFFFFF">
    <path android:fillColor="#FFFFFF"
        android:pathData="M4,4h6v2H6v4H4V4zM14,4h6v6h-2V6h-4V4zM4,14h2v4h4v2H4v-6zM18,14h2v6h-6v-2h4v-4zM7,7h4v4H7V7zM13,7h4v4h-4V7zM7,13h4v4H7v-4zM13,13h2v2h-2v-2zM15,15h2v2h-2v-2z"/>
</vector>
```

写 `android/app/src/main/res/layout/scan_widget.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/widget_root"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#161A20"
    android:padding="8dp">
    <ImageView
        android:layout_width="48dp"
        android:layout_height="48dp"
        android:layout_gravity="center"
        android:src="@drawable/ic_scan"
        android:contentDescription="扫一扫"/>
</FrameLayout>
```

写 `android/app/src/main/res/xml/scan_widget_info.xml`：

```xml
<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="72dp"
    android:minHeight="72dp"
    android:targetCellWidth="1"
    android:targetCellHeight="1"
    android:updatePeriodMillis="0"
    android:initialLayout="@layout/scan_widget"
    android:previewImage="@drawable/ic_scan"
    android:resizeMode="none"
    android:widgetCategory="home_screen"/>
```

- [ ] **Step 7: 编译验证（debug APK 装配）**

Run: `flutter build apk --debug`
Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk`（Gradle 无编译错误）。

- [ ] **Step 8: Commit**

```bash
git add android/
git commit -m "feat(android): manifest, scan_only launch, QS tile, home widget, WiFi channel"
```

---

## Task 10: scanner_screen（相机 + 手电筒 + 相册 + _done 闩锁 + scanOnly）

**Files:**
- Create: `lib/src/ui/scanner_screen.dart`

依赖前置：`ScanResultParser`（Task 2）、`HistoryStore`/`SettingsStore`（Task 5/6，经 provider 注入）、`showResultSheet`（Task 11）。mobile_scanner 7.x：`MobileScanner(controller:, onDetect:)`、`controller.toggleTorch()`、`controller.value.torchState`、`controller.analyzeImage(path)`。

- [ ] **Step 1: 实现**

写 `lib/src/ui/scanner_screen.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../core/history_entry.dart';
import '../core/scan_result.dart';
import '../services/history_store.dart';
import '../services/settings_store.dart';
import '../services/platform/launcher.dart';
import 'result_sheet.dart';

/// 扫码主界面。scanOnly=true 时为快捷入口（磁贴/小组件）：处理完动作即
/// SystemNavigator.pop() 退出，不进主壳。
class ScannerScreen extends StatefulWidget {
  final bool scanOnly;
  const ScannerScreen({super.key, this.scanOnly = false});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final _parser = const ScanResultParser();

  // 每帧重复检测 → 闩锁只处理一次，直到本次结果消费完毕。
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;
    final code = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (code == null) return;
    _busy = true;
    await _handle(code);
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    try {
      final result = await _controller.analyzeImage(file.path);
      final code = result?.barcodes
          .map((b) => b.rawValue)
          .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
      if (!mounted) return;
      if (code == null) {
        _toast('图片里没找到二维码');
        return;
      }
      _busy = true;
      await _handle(code);
    } catch (_) {
      if (mounted) _toast('识别失败');
    }
  }

  Future<void> _handle(String raw) async {
    final settings = context.read<SettingsStore>();
    final result = _parser.parse(raw);

    if (settings.haptics) HapticFeedback.mediumImpact();
    if (settings.keepHistory) {
      // ignore: use_build_context_synchronously
      await context.read<HistoryStore>().add(
            HistoryEntry.fromScan(result, DateTime.now()),
          );
    }

    // 自动打开（默认关，防钓鱼）：仅对 URL/AppLink 生效。
    if (settings.autoOpen &&
        (result is UrlResult || result is AppLinkResult)) {
      await const Launcher().open(result.raw);
      _finishOrResume(settings);
      return;
    }

    if (!mounted) return;
    await showResultSheet(context, result);
    _finishOrResume(settings);
  }

  void _finishOrResume(SettingsStore settings) {
    if (widget.scanOnly) {
      SystemNavigator.pop(); // 快捷入口：退出，不进主壳
      return;
    }
    // 主界面：连续模式立即继续，否则也解除闩锁等待下一次扫描。
    _busy = false;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(controller: _controller, onDetect: _onDetect),
        // 顶部工具条：手电筒 + 相册。
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          right: 12,
          child: Row(
            children: [
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controller,
                builder: (context, state, _) {
                  final on = state.torchState == TorchState.on;
                  return _RoundBtn(
                    icon: on ? Icons.flash_on : Icons.flash_off,
                    onTap: () => _controller.toggleTorch(),
                  );
                },
              ),
              const SizedBox(width: 8),
              _RoundBtn(icon: Icons.photo_library, onTap: _pickFromGallery),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 analyze（依赖 Task 11 的 result_sheet；先做 Task 11 再回来验证）**

Run: `flutter analyze lib/src/ui/scanner_screen.dart`
Expected: `No issues found!`（`showResultSheet` 已在 Task 11 存在）。

- [ ] **Step 3: Commit**

```bash
git add lib/src/ui/scanner_screen.dart
git commit -m "feat(ui): scanner screen with torch, gallery, scanOnly latch"
```

---

## Task 11: result_sheet（按类型给动作的底部面板）

**Files:**
- Create: `lib/src/ui/result_sheet.dart`

- [ ] **Step 1: 实现**

写 `lib/src/ui/result_sheet.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app/theme.dart';
import '../core/scan_result.dart';
import '../services/platform/launcher.dart';
import '../services/platform/wifi_connect.dart';

/// 弹出结果底部面板：按 [ScanResult] 类型给出对应动作。
Future<void> showResultSheet(BuildContext context, ScanResult result) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => _ResultSheet(result: result),
  );
}

class _ResultSheet extends StatelessWidget {
  final ScanResult result;
  const _ResultSheet({required this.result});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_title(result),
                style: TextStyle(color: t.muted, fontSize: 13)),
            const SizedBox(height: 6),
            SelectableText(result.raw,
                maxLines: 4,
                style: TextStyle(color: t.text, fontSize: 16)),
            const SizedBox(height: 16),
            ..._actions(context, result),
          ],
        ),
      ),
    );
  }

  String _title(ScanResult r) => switch (r) {
        UrlResult() => '网址',
        AppLinkResult() => '应用链接',
        WifiResult() => 'WiFi 网络',
        TelResult() => '电话',
        EmailResult() => '邮箱',
        GeoResult() => '位置',
        TextResult() => '文本',
      };

  List<Widget> _actions(BuildContext context, ScanResult r) {
    switch (r) {
      case UrlResult():
        return [
          _Primary('打开', Icons.open_in_browser,
              () => _open(context, r.raw)),
          _Sub('复制', () => _copy(context, r.raw)),
          _Sub('分享', () => _share(r.raw)),
        ];
      case AppLinkResult():
        return [
          _Primary('打开应用', Icons.open_in_new,
              () => _open(context, r.raw, fallbackMsg: '没有应用能打开此链接')),
          _Sub('复制', () => _copy(context, r.raw)),
        ];
      case WifiResult():
        return [
          _Primary('一键连接', Icons.wifi, () => _connectWifi(context, r)),
          _Sub('复制密码', () => _copy(context, r.password)),
          _Sub('复制名称', () => _copy(context, r.ssid)),
        ];
      case TelResult():
        return [
          _Primary('拨号', Icons.call, () => _open(context, 'tel:${r.number}')),
          _Sub('复制', () => _copy(context, r.number)),
        ];
      case EmailResult():
        return [
          _Primary('写邮件', Icons.email,
              () => _open(context, 'mailto:${r.address}')),
          _Sub('复制', () => _copy(context, r.address)),
        ];
      case GeoResult():
        return [
          _Primary('打开地图', Icons.map, () => _open(context, r.raw)),
          _Sub('复制', () => _copy(context, r.raw)),
        ];
      case TextResult():
        return [
          if (r.embeddedUrl != null)
            _Primary('打开链接', Icons.open_in_browser,
                () => _open(context, r.embeddedUrl!)),
          _Primary('复制', Icons.copy, () => _copy(context, r.raw)),
          _Sub('分享', () => _share(r.raw)),
        ];
    }
  }

  Future<void> _open(BuildContext context, String url,
      {String? fallbackMsg}) async {
    final ok = await const Launcher().open(url);
    if (!ok && context.mounted) {
      _snack(context, fallbackMsg ?? '无法打开');
    } else if (context.mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _connectWifi(BuildContext context, WifiResult r) async {
    // 先把密码放剪贴板，作为系统面板不可用时的回退。
    await Clipboard.setData(ClipboardData(text: r.password));
    final ok = await const WifiConnect().connect(
      ssid: r.ssid,
      password: r.password,
      security: r.security,
      hidden: r.hidden,
    );
    if (!context.mounted) return;
    _snack(context, ok ? '密码已复制，在系统面板确认连接' : 'WiFi 面板不可用，密码已复制');
    Navigator.of(context).pop();
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      _snack(context, '已复制');
      Navigator.of(context).pop();
    }
  }

  Future<void> _share(String text) => Share.share(text);

  void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _Primary extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _Primary(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: FilledButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
}

class _Sub extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Sub(this.label, this.onTap);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: OutlinedButton(onPressed: onTap, child: Text(label)),
      );
}
```

- [ ] **Step 2: 验证 analyze（scanner + result_sheet 一起过）**

Run: `flutter analyze lib/src/ui/`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/src/ui/result_sheet.dart
git commit -m "feat(ui): result action sheet per scan type"
```

---

## Task 12: 历史/设置界面 · 主壳 · 入口装配

**Files:**
- Create: `lib/src/ui/history_screen.dart`
- Create: `lib/src/ui/settings_screen.dart`
- Create: `lib/src/ui/home_shell.dart`
- Rewrite: `lib/main.dart`

- [ ] **Step 1: 写 history_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/scan_result.dart';
import '../services/history_store.dart';
import 'result_sheet.dart';

/// 历史列表：倒序（最新在前）、点击复现动作、滑动删除、一键清空。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const _icons = {
    'url': Icons.link,
    'applink': Icons.open_in_new,
    'wifi': Icons.wifi,
    'tel': Icons.call,
    'email': Icons.email,
    'geo': Icons.map,
    'text': Icons.notes,
  };

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final entries = store.entries;
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史'),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空',
              onPressed: () => _confirmClear(context, store),
            ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('还没有扫码记录'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return Dismissible(
                  key: ValueKey('${e.timestamp.microsecondsSinceEpoch}_$i'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => store.removeAt(i),
                  child: ListTile(
                    leading: Icon(_icons[e.type] ?? Icons.notes),
                    title: Text(e.content,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_fmt(e.timestamp)),
                    onTap: () => showResultSheet(
                        context, const ScanResultParser().parse(e.content)),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context, HistoryStore store) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空历史？'),
        content: const Text('此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('清空')),
        ],
      ),
    );
    if (ok == true) await store.clear();
  }

  String _fmt(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
```

- [ ] **Step 2: 写 settings_screen.dart**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/theme.dart';
import '../services/settings_store.dart';

/// 设置界面：开关 + 亮度偏好。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsStore>();
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('扫到即自动打开'),
            subtitle: const Text('仅网址/应用链接；默认关闭以防钓鱼'),
            value: s.autoOpen,
            onChanged: (v) => s.autoOpen = v,
          ),
          SwitchListTile(
            title: const Text('震动反馈'),
            value: s.haptics,
            onChanged: (v) => s.haptics = v,
          ),
          SwitchListTile(
            title: const Text('提示音'),
            value: s.beep,
            onChanged: (v) => s.beep = v,
          ),
          SwitchListTile(
            title: const Text('记录历史'),
            value: s.keepHistory,
            onChanged: (v) => s.keepHistory = v,
          ),
          SwitchListTile(
            title: const Text('连续扫描'),
            subtitle: const Text('处理完一个继续扫下一个'),
            value: s.continuous,
            onChanged: (v) => s.continuous = v,
          ),
          const Divider(),
          ListTile(
            title: const Text('外观'),
            trailing: DropdownButton<SaoBrightness>(
              value: s.brightness,
              onChanged: (v) => v == null ? null : s.brightness = v,
              items: const [
                DropdownMenuItem(
                    value: SaoBrightness.system, child: Text('跟随系统')),
                DropdownMenuItem(value: SaoBrightness.dark, child: Text('深色')),
                DropdownMenuItem(value: SaoBrightness.light, child: Text('浅色')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: 写 home_shell.dart（底部导航：扫码/历史/设置）**

```dart
import 'package:flutter/material.dart';

import 'history_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

/// 普通启动首屏：首屏即扫码，底部切历史/设置。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ScannerScreen(),
          HistoryScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.qr_code_scanner), label: '扫码'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 重写 main.dart（读 launch mode + 装配 provider + 主题）**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'src/app/theme.dart';
import 'src/services/history_store.dart';
import 'src/services/settings_store.dart';
import 'src/ui/home_shell.dart';
import 'src/ui/scanner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 冷启动优化：launch mode 探测 + 两个 store 加载三者并行（Dart 3 record .wait），
  // 不串行 await，尽量缩短到首帧的时间。
  final (mode, history, settings) = await (
    _launchMode(),
    HistoryStore.forApp(),
    SettingsStore.forApp(),
  ).wait;

  runApp(SaoLeApp(
    scanOnly: mode == 'scan_only',
    history: history,
    settings: settings,
  ));
}

/// 磁贴/小组件带 mode=scan_only 拉起时直入扫码；普通启动为 'normal'。
Future<String> _launchMode() async {
  try {
    return await const MethodChannel('saole/launch')
            .invokeMethod<String>('getMode') ??
        'normal';
  } on PlatformException {
    return 'normal';
  } on MissingPluginException {
    return 'normal';
  }
}

class SaoLeApp extends StatelessWidget {
  final bool scanOnly;
  final HistoryStore history;
  final SettingsStore settings;
  const SaoLeApp({
    super.key,
    required this.scanOnly,
    required this.history,
    required this.settings,
  });

  ThemeMode _themeMode(SaoBrightness b) => switch (b) {
        SaoBrightness.system => ThemeMode.system,
        SaoBrightness.dark => ThemeMode.dark,
        SaoBrightness.light => ThemeMode.light,
      };

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: history),
        ChangeNotifierProvider.value(value: settings),
      ],
      child: Consumer<SettingsStore>(
        builder: (context, s, _) => MaterialApp(
          title: '扫了',
          debugShowCheckedModeBanner: false,
          theme: buildSaoTheme(Brightness.light),
          darkTheme: buildSaoTheme(Brightness.dark),
          themeMode: _themeMode(s.brightness),
          home: scanOnly
              ? const Scaffold(body: ScannerScreen(scanOnly: true))
              : const HomeShell(),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: 全量 analyze + test**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: All tests passed!（core + services 全部单测）

- [ ] **Step 6: Commit**

```bash
git add lib/
git commit -m "feat(ui): history/settings screens, home shell, app entry wiring"
```

---

## Task 13: 独立签名 keystore + release signingConfig

**Files:**
- Create: `android/key.properties`（**git-ignored**）
- Create: `android/key.properties.example`
- Create keystore: `android/saole-upload.jks`（**git-ignored**，独立于 AVA 的 `~/ava-upload.jks`）
- Modify: `.gitignore`
- 复用 Task 9 已就位的 `build.gradle.kts` signingConfig（照搬自 AVA，见下确认）

- [ ] **Step 1: 生成独立 keystore（非交互）**

Run:
```bash
keytool -genkeypair -v \
  -keystore android/saole-upload.jks \
  -alias saole -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass CHANGE_ME_STORE -keypass CHANGE_ME_KEY \
  -dname "CN=dotSlash, O=dotSlash, C=CN"
```
Expected: 生成 `android/saole-upload.jks`。（执行者应把 `CHANGE_ME_*` 换成真实强密码。）

- [ ] **Step 2: 写 key.properties 与示例**

写 `android/key.properties`（真实值，**不提交**）：
```properties
storePassword=CHANGE_ME_STORE
keyPassword=CHANGE_ME_KEY
keyAlias=saole
storeFile=saole-upload.jks
```

写 `android/key.properties.example`（可提交模板）：
```properties
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=saole
storeFile=saole-upload.jks
```

- [ ] **Step 3: 确认 build.gradle.kts 有 signingConfig（照搬 AVA 模板）**

确认 `android/app/build.gradle.kts` 顶部有读取 `key.properties` 的逻辑与 `signingConfigs { create("release") {...} }`、release buildType 用 `hasReleaseSigning ? release : debug`。若 Task 9 改包名时未加，则照搬 `/mnt/c/Users/freefrank/ownCloud/Git/AnotherVaporAuth/app/android/app/build.gradle.kts` 的 signing 结构（含 `Properties()` 加载、`gradle.taskGraph.whenReady` fail-closed 的 bundleRelease 保护）。

- [ ] **Step 4: 更新 .gitignore**

在 `.gitignore` 追加：
```
# 签名密钥（绝不提交）
android/key.properties
android/*.jks
android/app/upload-keystore.jks
```

- [ ] **Step 5: 验证 release 构建可签名**

Run: `flutter build apk --release`
Expected: `✓ Built build/app/outputs/flutter-apk/app-release.apk`，用 release keystore 签名（非 debug 回退）。

- [ ] **Step 6: Commit（确保 jks/key.properties 未被追踪）**

```bash
git status --porcelain   # 确认 android/saole-upload.jks 与 android/key.properties 不在列表
git add android/key.properties.example .gitignore android/app/build.gradle.kts
git commit -m "build(android): independent release keystore + signing config"
```

---

## Task 14: CI 门禁 + 权限降级 + 最终验收

**Files:**
- Create: `.github/workflows/ci.yml`（照搬 AVA analyze/test 门禁）
- Modify: `lib/src/ui/scanner_screen.dart`（相机权限拒绝的 errorBuilder 引导）

- [ ] **Step 1: 加相机权限拒绝引导（scanner_screen 的 MobileScanner errorBuilder）**

在 `lib/src/ui/scanner_screen.dart` 的 `MobileScanner(...)` 增加 `errorBuilder`：

```dart
MobileScanner(
  controller: _controller,
  onDetect: _onDetect,
  errorBuilder: (context, error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography, size: 48),
            const SizedBox(height: 12),
            const Text('无法访问相机',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('请在系统设置中授予相机权限，或改用相册识图。',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _pickFromGallery,
              child: const Text('从相册识别'),
            ),
          ],
        ),
      ),
    );
  },
),
```

Run: `flutter analyze lib/src/ui/scanner_screen.dart`
Expected: `No issues found!`

- [ ] **Step 2: 写 CI 工作流（照搬 AVA analyze/test 门禁）**

写 `.github/workflows/ci.yml`：

```yaml
name: CI
on:
  push:
    branches: [main, master]
  pull_request:

jobs:
  analyze-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.44.4'
          channel: stable
      - run: flutter pub get
      - run: flutter analyze
      - run: flutter test
```

- [ ] **Step 3: 本地跑一遍门禁（push 前必过）**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` 且 `All tests passed!`

- [ ] **Step 4: 真机/模拟器冒烟（人工验收，逐项打勾）**

Run: `flutter run --release`（连接 Android 设备/模拟器）

逐项确认：
- [ ] 冷启动直接进扫码画面
- [ ] 扫一个网址 QR → 弹面板 → "打开" 唤起浏览器；"复制"/"分享" 可用
- [ ] 扫 WiFi QR（`WIFI:S:Test;T:WPA;P:12345678;;`）→ "一键连接" 拉起系统面板 / 回退复制
- [ ] 手电筒按钮切换成功
- [ ] 相册选一张含码图片 → 识别出结果
- [ ] 历史标签页出现刚才记录；滑动删除、清空可用；点击复现动作
- [ ] 设置里关掉"记录历史"后再扫，历史不新增
- [ ] 添加桌面小组件，点击 → 直接进扫码（scan_only），扫完自动退出
- [ ] Quick Settings 加"扫了"磁贴，点击 → 直接进扫码，扫完自动退出
- [ ] 深色/浅色切换生效

- [ ] **Step 5: Commit**

```bash
git add .github/ lib/src/ui/scanner_screen.dart
git commit -m "ci: analyze/test gate; feat: camera-permission fallback guide"
```

---

## 完成标准

- `flutter analyze` 零问题、`flutter test` 全绿（core parser + history + wifi channel mock 覆盖）。
- MVP 功能清单全部可用：扫码识别/分类/动作、手电筒、相册识图、历史、URL/App 直开、WiFi 一键连接、磁贴、桌面小组件、设置。
- release APK 用独立 keystore 签名，`saole-upload.jks` 与 `key.properties` 未进版本库。
- 健壮性：畸形 WiFi 串、超长 uint64、非拉丁文本、空串、损坏历史文件、相机权限拒绝均不崩。

## 明确不做（v2 / 否决）

OCR（架构预留）、生成/分享自己的二维码、iOS/桌面、云同步、批量扫描导出。
