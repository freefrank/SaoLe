import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/date_bucket.dart';
import '../core/history_entry.dart';
import '../core/scan_result.dart';
import '../services/history_store.dart';
import 'result_sheet.dart';
import 'type_style.dart';

/// 历史列表：按日期分组（今天/昨天/更早）、类型筛选、
/// 点击复现动作、滑动删除可撤销、一键清空。
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String? _filter; // null = 全部

  @override
  Widget build(BuildContext context) {
    final store = context.watch<HistoryStore>();
    final all = store.entries;
    // 只给实际存在的类型出 chip；筛选中的类型被删空后自动回到全部。
    final presentTypes = [
      for (final t in TypeStyle.orderedTypes)
        if (all.any((e) => e.type == t)) t,
    ];
    if (_filter != null && !presentTypes.contains(_filter)) _filter = null;
    final entries = _filter == null
        ? all
        : [
            for (final e in all)
              if (e.type == _filter) e,
          ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史'),
        actions: [
          if (all.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空',
              onPressed: () => _confirmClear(context, store),
            ),
        ],
      ),
      body: all.isEmpty
          ? _empty(context)
          : Column(
              children: [
                if (presentTypes.length > 1) _filterChips(presentTypes),
                Expanded(child: _groupedList(context, store, entries)),
              ],
            ),
    );
  }

  Widget _empty(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_scanner, size: 56, color: outline),
          const SizedBox(height: 12),
          const Text('还没有扫码记录'),
          const SizedBox(height: 4),
          Text('扫到的内容会出现在这里', style: TextStyle(fontSize: 13, color: outline)),
        ],
      ),
    );
  }

  Widget _filterChips(List<String> types) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: const Text('全部'),
              selected: _filter == null,
              onSelected: (_) => setState(() => _filter = null),
            ),
          ),
          for (final t in types)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                avatar: Icon(
                  TypeStyle.of(t).icon,
                  size: 18,
                  color: TypeStyle.of(t).color,
                ),
                label: Text(TypeStyle.of(t).label),
                selected: _filter == t,
                onSelected: (_) => setState(() => _filter = t),
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupedList(
    BuildContext context,
    HistoryStore store,
    List<HistoryEntry> entries,
  ) {
    if (entries.isEmpty) {
      return const Center(child: Text('没有此类型的记录'));
    }
    // 摊平成 [分组头, 条目, 条目, 分组头, …]，倒序列表天然分桶连续。
    final now = DateTime.now();
    final rows = <Object>[];
    DateBucket? current;
    for (final e in entries) {
      final b = bucketOf(e.timestamp, now);
      if (b != current) {
        rows.add(b);
        current = b;
      }
      rows.add(e);
    }

    return ListView.builder(
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row is DateBucket) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              row.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          );
        }
        final e = row as HistoryEntry;
        final style = TypeStyle.of(e.type);
        return Dismissible(
          key: ObjectKey(e),
          direction: DismissDirection.endToStart,
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          onDismissed: (_) => _removeWithUndo(context, store, e),
          child: ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: style.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(style.icon, color: style.color, size: 20),
            ),
            title: Text(
              e.content,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_fmt(e.timestamp)),
            onTap: () => showResultSheet(
              context,
              const ScanResultParser().parse(e.content),
            ),
          ),
        );
      },
    );
  }

  // 删除即时生效，但给 4 秒撤销窗口插回原位（误触滑删可救）。
  // 索引取自完整列表（筛选视图的下标对不上存储）。
  void _removeWithUndo(
    BuildContext context,
    HistoryStore store,
    HistoryEntry e,
  ) {
    final index = store.entries.indexOf(e);
    store.removeEntry(e);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text('已删除'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => store.insertAt(index, e),
          ),
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
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
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
