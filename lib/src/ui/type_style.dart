import 'package:flutter/material.dart';

import '../core/history_entry.dart';
import '../core/scan_result.dart';

/// 各扫码类型的图标与识别色：结果面板徽章、历史列表共用一套语义。
/// 颜色选自 Material 系，明暗两主题下与深浅背景对比都够。
class TypeStyle {
  final IconData icon;
  final Color color;
  final String label;
  const TypeStyle(this.icon, this.color, this.label);

  static const _styles = <String, TypeStyle>{
    'url': TypeStyle(Icons.link_rounded, Color(0xFF2F6BFF), '网址'),
    'applink': TypeStyle(Icons.open_in_new_rounded, Color(0xFF8B5CF6), '应用'),
    'wifi': TypeStyle(Icons.wifi_rounded, Color(0xFF10B981), 'WiFi'),
    'tel': TypeStyle(Icons.call_rounded, Color(0xFF06B6D4), '电话'),
    'email': TypeStyle(Icons.email_rounded, Color(0xFFF59E0B), '邮箱'),
    'geo': TypeStyle(Icons.map_rounded, Color(0xFFEF4444), '位置'),
    'fido': TypeStyle(Icons.key_rounded, Color(0xFFEAB308), 'FIDO'),
    'text': TypeStyle(Icons.notes_rounded, Color(0xFF64748B), '文本'),
  };

  static const _fallback = TypeStyle(
    Icons.notes_rounded,
    Color(0xFF64748B),
    '文本',
  );

  static TypeStyle of(String type) => _styles[type] ?? _fallback;

  static TypeStyle ofResult(ScanResult r) => of(HistoryEntry.kindOf(r));

  /// 历史筛选 chips 的展示顺序。
  static const orderedTypes = [
    'url',
    'wifi',
    'text',
    'applink',
    'tel',
    'email',
    'geo',
    'fido',
  ];
}
