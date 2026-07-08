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
    await s.removeAt(0);
    expect(s.entries.single.content, 'a');
    await s.clear();
    expect(s.entries, isEmpty);
  });

  test('removeEntry 按实体删除中间一条', () async {
    final s = HistoryStore(file: file);
    await s.load();
    await s.add(entry('a'));
    await s.add(entry('b'));
    await s.add(entry('c'));
    // entries 现为 ['c', 'b', 'a']（最新在前），按实体删中间的 'b'。
    final middle = s.entries.firstWhere((e) => e.content == 'b');
    await s.removeEntry(middle);
    expect(s.entries.map((e) => e.content).toList(), ['c', 'a']);

    final reloaded = HistoryStore(file: file);
    await reloaded.load();
    expect(reloaded.entries.map((e) => e.content).toList(), ['c', 'a']);
  });

  test('notifyListeners 在变更时触发', () async {
    final s = HistoryStore(file: file);
    await s.load();
    var n = 0;
    s.addListener(() => n++);
    await s.add(entry('x'));
    expect(n, greaterThan(0));
  });

  test('insertAt 插回原位置并落盘（撤销删除）', () async {
    final s = HistoryStore(file: file);
    await s.load();
    await s.add(entry('a'));
    await s.add(entry('b'));
    await s.add(entry('c'));
    // 现为 ['c','b','a']，删中间再插回原位。
    final removed = s.entries[1];
    await s.removeAt(1);
    await s.insertAt(1, removed);
    expect(s.entries.map((e) => e.content).toList(), ['c', 'b', 'a']);

    final reloaded = HistoryStore(file: file);
    await reloaded.load();
    expect(reloaded.entries.map((e) => e.content).toList(), ['c', 'b', 'a']);
  });

  test('insertAt 越界索引夹到边界，不崩', () async {
    final s = HistoryStore(file: file);
    await s.load();
    await s.add(entry('a'));
    await s.insertAt(99, entry('tail'));
    expect(s.entries.map((e) => e.content).toList(), ['a', 'tail']);
    await s.insertAt(-1, entry('head'));
    expect(s.entries.first.content, 'head');
  });

  test('单条损坏记录只跳过该条，其余保留', () async {
    // good1 / bad（ts 非法）/ good2：load 应得到两条好的。
    await file.writeAsString(
      '['
      '{"content":"good1","type":"text","ts":"2026-01-01T00:00:00.000Z"},'
      '{"content":"bad","type":"text","ts":"not-a-date"},'
      '{"content":"good2","type":"text","ts":"2026-01-02T00:00:00.000Z"}'
      ']',
    );
    final s = HistoryStore(file: file);
    await s.load();
    expect(s.entries.map((e) => e.content).toList(), ['good1', 'good2']);
  });

  test('字段缺失的记录跳过，不影响其余', () async {
    await file.writeAsString(
      '['
      '{"type":"text","ts":"2026-01-01T00:00:00.000Z"},'
      '{"content":"ok","type":"text","ts":"2026-01-01T00:00:00.000Z"}'
      ']',
    );
    final s = HistoryStore(file: file);
    await s.load();
    expect(s.entries.single.content, 'ok');
  });

  test('写盘原子：flush 后不残留临时文件，内容完整可读', () async {
    final s = HistoryStore(file: file);
    await s.load();
    await s.add(entry('a'));
    await s.add(entry('b'));
    expect(File('${file.path}.tmp').existsSync(), isFalse);
    final reloaded = HistoryStore(file: file);
    await reloaded.load();
    expect(reloaded.entries.length, 2);
  });

  test('超过上限时丢弃最旧的记录', () async {
    final s = HistoryStore(file: file);
    await s.load();
    for (var i = 0; i < HistoryStore.maxEntries + 10; i++) {
      await s.add(entry('e$i'));
    }
    expect(s.entries.length, HistoryStore.maxEntries);
    // 最新在前：最后加的在头部，最早的已被丢弃。
    expect(s.entries.first.content, 'e${HistoryStore.maxEntries + 9}');
    expect(s.entries.any((e) => e.content == 'e0'), isFalse);

    final reloaded = HistoryStore(file: file);
    await reloaded.load();
    expect(reloaded.entries.length, HistoryStore.maxEntries);
  });

  test('load 对超长文件也截断到上限', () async {
    final items = [
      for (var i = 0; i < HistoryStore.maxEntries + 5; i++)
        '{"content":"e$i","type":"text","ts":"2026-01-01T00:00:00.000Z"}',
    ];
    await file.writeAsString('[${items.join(',')}]');
    final s = HistoryStore(file: file);
    await s.load();
    expect(s.entries.length, HistoryStore.maxEntries);
    expect(s.entries.first.content, 'e0'); // 文件序保留，尾部截断
  });
}
