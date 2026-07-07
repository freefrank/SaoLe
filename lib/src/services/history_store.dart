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
