import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'subscription_reader.dart';

/// 分享页解析：很多采集站把「分享页 / 播放器页」当成播放地址给出，
/// 页面本身里其实就写着真实的 m3u8。这里只做**静态读取**——拿 HTML，
/// 从文本里找媒体地址，不执行页面脚本。
///
/// 拿不到就明确返回失败原因（比如优酷那种必须跑 JS 才出流的站），
/// 不假装能播。
class PageResolveResult {
  const PageResolveResult.success(this.streamUrl, {this.via = ''})
    : reason = null;
  const PageResolveResult.failed(this.reason)
    : streamUrl = null,
      via = '';

  final String? streamUrl;
  final String? reason;

  /// 命中的位置说明，调试时看是哪条规则捞到的。
  final String via;

  bool get ok => streamUrl != null;
}

class PageStreamResolver {
  const PageStreamResolver({
    this.timeout = const Duration(seconds: 12),
    this.maxBytes = 2 * 1024 * 1024,
  });

  final Duration timeout;
  final int maxBytes;

  static final _absolute = RegExp(
    r'''https?://[^\s"'<>()\[\]{}]+?\.(?:m3u8|mp4)(?:\?[^\s"'<>()\[\]{}]*)?''',
    caseSensitive: false,
  );
  static final _quoted = RegExp(
    r'''(?:"|'|`)([^"'`<>]*?\.(?:m3u8|mp4)(?:\?[^"'`<>]*)?)(?:"|'|`)''',
    caseSensitive: false,
  );

  Future<PageResolveResult> resolve(
    String pageUrl, {
    String referer = '',
    HttpClient? client,
  }) async {
    final page = Uri.tryParse(pageUrl.trim());
    if (page == null) return const PageResolveResult.failed('地址格式不对');
    try {
      SubscriptionReader.validateWebUri(page);
    } on FormatException catch (error) {
      return PageResolveResult.failed(error.message);
    }
    final http = client ?? HttpClient()..connectionTimeout = timeout;
    try {
      final request = await http.getUrl(page).timeout(timeout);
      request.followRedirects = true;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
            'Mobile/15E148 Safari/604.1',
      );
      if (referer.isNotEmpty) request.headers.set('Referer', referer);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        return PageResolveResult.failed('页面返回 HTTP ${response.statusCode}');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxBytes) {
          return const PageResolveResult.failed('页面太大，放弃解析');
        }
      }
      final html = utf8.decode(builder.takeBytes(), allowMalformed: true);
      final found = extract(html, base: page);
      if (found == null) {
        return const PageResolveResult.failed('页面里没有直链，需要跑网页脚本（本版不执行）');
      }
      return PageResolveResult.success(found.url, via: found.via);
    } on TimeoutException {
      return const PageResolveResult.failed('页面超时');
    } on SocketException {
      return const PageResolveResult.failed('连不上这个页面');
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// 纯函数：从页面文本里挑一个媒体地址。抽出来是为了能用录下来的页面做测试。
  static ({String url, String via})? extract(String html, {required Uri base}) {
    // 转义斜杠先在入口还原，这样 resolve() 与直接调用 extract() 同一条规则。
    html = _unescape(html);
    for (final match in _absolute.allMatches(html)) {
      final url = match.group(0);
      if (url != null) return (url: url, via: 'absolute');
    }
    for (final match in _quoted.allMatches(html)) {
      final raw = match.group(1);
      if (raw == null || raw.isEmpty) continue;
      final resolved = base.resolve(raw);
      if (!['http', 'https'].contains(resolved.scheme) || resolved.host.isEmpty) {
        continue;
      }
      return (url: resolved.toString(), via: 'relative');
    }
    return null;
  }

  /// JSON 里常见 \\/ 与 \\u002F 两种转义，先把它们还原成普通斜杠。
  static String _unescape(String html) => html
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u002F', '/')
      .replaceAll(r'\u002f', '/');
}
