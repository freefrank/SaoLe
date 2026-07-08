import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/history_entry.dart';

/// 历史记录存储：内存列表 + JSON 文件落盘。倒序（最新在前）。
/// 损坏文件读取时优雅退化为空历史，绝不崩。
class HistoryStore extends ChangeNotifier {
  /// 历史条数上限，超出丢最旧的（无限增长会拖慢每次全量落盘）。
  static const maxEntries = 500;

  final File file;
  final List<HistoryEntry> _entries = [];

  HistoryStore({required this.file});

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
        if (_entries.length >= maxEntries) break;
        // 单条损坏只跳过该条，不连累整个历史。
        try {
          _entries.add(HistoryEntry.fromJson(j as Map<String, dynamic>));
        } catch (_) {}
      }
    } catch (_) {
      _entries.clear();
    }
    notifyListeners();
  }

  Future<void> add(HistoryEntry e) async {
    _entries.insert(0, e);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    await _flush();
  }

  /// 插回指定位置（撤销删除用）。索引越界时夹到边界。
  Future<void> insertAt(int index, HistoryEntry e) async {
    _entries.insert(index.clamp(0, _entries.length), e);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
    await _flush();
  }

  Future<void> removeEntry(HistoryEntry e) async {
    if (_entries.remove(e)) {
      notifyListeners();
      await _flush();
    }
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _entries.length) return;
    _entries.removeAt(index);
    notifyListeners();
    await _flush();
  }

  Future<void> clear() async {
    _entries.clear();
    notifyListeners();
    await _flush();
  }

  Future<void> _flush() async {
    try {
      final data = jsonEncode(_entries.map((e) => e.toJson()).toList());
      // 先写临时文件再 rename：进程中途被杀也不会留下半截 JSON。
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      // 落盘失败不影响内存态与 UI；下次变更再尝试。
    }
  }
}
