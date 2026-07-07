import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/scan_result.dart';
import '../services/history_store.dart';
import 'result_sheet.dart';

/// 历史列表：倒序、点击复现动作、滑动删除、一键清空。
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const _icons = {
    'url': Icons.link, 'applink': Icons.open_in_new, 'wifi': Icons.wifi,
    'tel': Icons.call, 'email': Icons.email, 'geo': Icons.map,
    'fido': Icons.key, 'text': Icons.notes,
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
                  key: ObjectKey(e),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) => store.removeEntry(e),
                  child: ListTile(
                    leading: Icon(_icons[e.type] ?? Icons.notes),
                    title: Text(e.content, maxLines: 1, overflow: TextOverflow.ellipsis),
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('清空')),
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
