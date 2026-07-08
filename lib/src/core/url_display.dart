/// 把 http/https URL 按原文拆成 host 前 / host / host 后三段，
/// 供 UI 富文本高亮域名（防钓鱼：一眼看清真实站点）。
/// 非 http(s) 或解析失败返回 null；纯函数、绝不抛异常。
({String prefix, String host, String suffix})? splitUrlForDisplay(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return null;
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  // Uri 会把 host 规范成小写；按小写在原文里定位，切片保留原样大小写。
  final idx = raw.toLowerCase().indexOf(uri.host.toLowerCase());
  if (idx < 0) return null;
  final end = idx + uri.host.length;
  return (
    prefix: raw.substring(0, idx),
    host: raw.substring(idx, end),
    suffix: raw.substring(end),
  );
}
