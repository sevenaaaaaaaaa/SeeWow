import 'dart:convert';

/// 把一次粘贴的多行内容整理成候选地址：去空行、去注释、去重、保序。
///
/// 支持三种常见粘贴形态：
/// - 一行一个地址；
/// - 从别处抄来的「名称, 地址」或「名称 地址」——取行里最后一个像地址的部分；
/// - 带 `#` 或 `//` 的注释行，直接忽略。
List<String> bulkEntries(String text, {bool webOnly = false}) {
  final seen = <String>{};
  final result = <String>[];
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith('//')) continue;
    final tokens = line.split(RegExp(r'[\s,，;；]+'));
    var candidate = tokens.lastWhere(_looksLikeTarget, orElse: () => line);
    candidate = candidate.trim();
    if (candidate.isEmpty) continue;
    if (webOnly) {
      final uri = Uri.tryParse(candidate);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty) {
        continue;
      }
    }
    final key = candidate.endsWith('/') && candidate.length > 1
        ? candidate.substring(0, candidate.length - 1)
        : candidate;
    if (seen.add(key)) result.add(candidate);
  }
  return result;
}

bool _looksLikeTarget(String token) {
  if (token.isEmpty) return false;
  if (token.contains('://')) return true;
  if (token.startsWith('/') || token.startsWith('~')) return true;
  if (RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(token)) return true;
  return false;
}
