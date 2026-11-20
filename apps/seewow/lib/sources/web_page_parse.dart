/// 页面 → 可播地址的纯文本处理：不联网、不起 WebView，方便单测。
///
/// 分享页的常见形态有三种：
/// 1. 参数里裹着真实地址：`https://jx.example/?url=https%3A%2F%2F…m3u8`；
/// 2. 页面里藏着播放地址：`{"url":"https:\\/\\/…m3u8"}`；
/// 3. 页面自己发请求：抓到以 m3u8 结尾的资源就算命中。
final _mediaPattern = RegExp(
  r'''https?:[^\s"'<>\\]+?\.(?:m3u8|mp4|flv|ts|mkv|m4v)(?:\?[^\s"'<>\\]*)?''',
  caseSensitive: false,
);

/// 已知的播放器页 / 分享页域名：这些 URL 不是媒体文件。
const _pageHosts = [
  'youku.com',
  'v.qq.com',
  'iqiyi.com',
  'bilibili.com',
  'mgtv.com',
  'le.com',
  'sohu.com',
  'pptv.com',
  '1905.com',
];

/// 这段文本里第一个像媒体地址的东西；没有就返回 null。
String? mediaUrlFrom(String text) {
  final decoded = text
      .replaceAll(r'\/', '/')
      .replaceAll('&amp;', '&')
      .replaceAll('\\u0026', '&');
  final match = _mediaPattern.firstMatch(decoded);
  return match?.group(0);
}

/// `?url=` / `&url=` 里裹着的地址，解一层就返回；没有就返回 null。
String? unwrapUrlParam(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri == null) return null;
  for (final key in const ['url', 'u', 'v', 'src']) {
    final raw = uri.queryParameters[key];
    if (raw == null || raw.isEmpty) continue;
    final candidate = Uri.tryParse(raw);
    if (candidate != null && ['http', 'https'].contains(candidate.scheme)) {
      return candidate.toString();
    }
  }
  return null;
}

/// 是否「不是媒体文件、需要网页解析」的地址。
bool isSharePageUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !['http', 'https'].contains(uri.scheme)) return false;
  if (uri.host.isEmpty) return false;
  if (mediaUrlFrom(url) != null) return false;
  final host = uri.host.toLowerCase();
  if (_pageHosts.any((page) => host == page || host.endsWith('.$page'))) {
    return true;
  }
  final path = uri.path.toLowerCase();
  return path.contains('/share/') || path.contains('/play/');
}
