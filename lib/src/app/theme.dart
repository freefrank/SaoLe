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

  static SaoTokens of(Brightness b) => b == Brightness.light ? light : dark;

  @override
  SaoTokens copyWith({Color? accent}) => SaoTokens(
    brightness: brightness,
    bg: bg,
    panel: panel,
    line: line,
    text: text,
    muted: muted,
    accent: accent ?? this.accent,
    good: good,
    bad: bad,
    radius: radius,
  );

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

/// [dynamicScheme] 来自系统壁纸取色（Android 12+ Material You）；
/// 传 null 时退回品牌蓝。中性面板/背景保持自有令牌，只让主色跟随系统。
ThemeData buildSaoTheme(Brightness brightness, {ColorScheme? dynamicScheme}) {
  var t = SaoTokens.of(brightness);
  final scheme = dynamicScheme != null
      ? dynamicScheme.copyWith(error: t.bad, surface: t.panel)
      : ColorScheme.fromSeed(
          seedColor: t.accent,
          brightness: brightness,
        ).copyWith(primary: t.accent, error: t.bad, surface: t.panel);
  if (dynamicScheme != null) t = t.copyWith(accent: scheme.primary);

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
