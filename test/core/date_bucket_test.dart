import 'package:flutter_test/flutter_test.dart';
import 'package:saole/src/core/date_bucket.dart';

void main() {
  final now = DateTime(2026, 7, 7, 15, 30); // 本地时间下午

  test('同一天任何时刻 → today', () {
    expect(bucketOf(DateTime(2026, 7, 7, 0, 0), now), DateBucket.today);
    expect(bucketOf(DateTime(2026, 7, 7, 23, 59), now), DateBucket.today);
  });

  test('昨天（含深夜边界）→ yesterday', () {
    expect(bucketOf(DateTime(2026, 7, 6, 23, 59), now), DateBucket.yesterday);
    expect(bucketOf(DateTime(2026, 7, 6, 0, 0), now), DateBucket.yesterday);
  });

  test('前天及更早 → earlier', () {
    expect(bucketOf(DateTime(2026, 7, 5, 23, 59), now), DateBucket.earlier);
    expect(bucketOf(DateTime(2025, 1, 1), now), DateBucket.earlier);
  });

  test('未来时间戳（时钟漂移）按 today 处理', () {
    expect(bucketOf(DateTime(2026, 7, 8, 1, 0), now), DateBucket.today);
  });

  test('label 齐全', () {
    expect(DateBucket.today.label, '今天');
    expect(DateBucket.yesterday.label, '昨天');
    expect(DateBucket.earlier.label, '更早');
  });
}
