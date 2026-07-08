/// 历史列表的日期分组：今天 / 昨天 / 更早。
enum DateBucket {
  today('今天'),
  yesterday('昨天'),
  earlier('更早');

  final String label;
  const DateBucket(this.label);
}

/// 按本地日历日分桶。未来时间戳（时钟漂移）归入今天。
DateBucket bucketOf(DateTime ts, DateTime now) {
  final t = ts.toLocal();
  final n = now.toLocal();
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(n.year, n.month, n.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return DateBucket.today;
  if (diff == 1) return DateBucket.yesterday;
  return DateBucket.earlier;
}
