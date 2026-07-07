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

  test('notifyListeners 在变更时触发', () async {
    final s = HistoryStore(file: file);
    await s.load();
    var n = 0;
    s.addListener(() => n++);
    await s.add(entry('x'));
    expect(n, greaterThan(0));
  });
}
