import 'dart:convert';
import 'dart:io';

/// One entry from a WebDAV PROPFIND response.
class DavEntry {
  DavEntry({required this.url, required this.name, required this.isDir, required this.size, required this.modified});

  final Uri url;
  final String name;
  final bool isDir;
  final int size;
  final DateTime? modified;

  bool get isVideo {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return false;
    return videoExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  static const videoExtensions = {
    'mp4', 'mkv', 'mov', 'm4v', 'avi', 'ts', 'm2ts', 'mts', 'webm', 'wmv',
    'flv', 'rmvb', 'rm', 'ogv', 'mpg', 'mpeg', 'vob', '3gp',
  };
}

class WebDavException implements Exception {
  WebDavException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => statusCode == null ? message : '$message (HTTP $statusCode)';
}

/// Minimal WebDAV client: Basic auth, Depth-1 listing, HEAD probe.
///
/// Playback does not go through this client: the player receives the file URL
/// plus the same auth header, so libmpv streams ranges directly.
class WebDavClient {
  WebDavClient(this.baseUri, {this.username = '', this.password = '', HttpClient? httpClient})
      : _http = httpClient ?? HttpClient();

  final Uri baseUri;
  final String username;
  final String password;
  final HttpClient _http;

  static const _propfindBody =
      '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:resourcetype/><d:getcontentlength/>'
      '<d:getcontenttype/><d:getlastmodified/>'
      '</d:prop></d:propfind>';

  Map<String, String> get authHeaders {
    if (username.isEmpty && password.isEmpty) return const {};
    final token = base64Encode(utf8.encode('$username:$password'));
    return {'Authorization': 'Basic $token', 'User-Agent': 'SeeWow/1.0'};
  }

  Future<List<DavEntry>> list(Uri uri) async {
    final request = await _http.openUrl('PROPFIND', uri).timeout(const Duration(seconds: 20));
    authHeaders.forEach(request.headers.set);
    request.headers.set('Depth', '1');
    request.headers.set('Content-Type', 'application/xml; charset=utf-8');
    request.add(utf8.encode(_propfindBody));
    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 401) throw WebDavException('用户名或密码不正确', statusCode: 401);
    if (response.statusCode >= 400) {
      throw WebDavException('服务器返回 ${response.statusCode}', statusCode: response.statusCode);
    }
    return parseMultistatus(body, uri);
  }

  Future<bool> exists(Uri uri) async {
    final request = await _http.openUrl('HEAD', uri).timeout(const Duration(seconds: 15));
    authHeaders.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 20));
    await response.drain<void>();
    return response.statusCode >= 200 && response.statusCode < 300;
  }

  void close() => _http.close(force: true);

  /// Parses a 207 Multi-Status body. Namespace prefixes (d:, D:, none) are all
  /// tolerated because servers disagree about them.
  static List<DavEntry> parseMultistatus(String xml, Uri requestUri) {
    final entries = <DavEntry>[];
    final blocks = RegExp(r'<(?:[\w-]+:)?response\b[^>]*>([\s\S]*?)</(?:[\w-]+:)?response>', caseSensitive: false)
        .allMatches(xml);
    final requestedPath = requestUri.path.endsWith('/') ? requestUri.path : '${requestUri.path}/';
    for (final block in blocks) {
      final inner = block.group(1) ?? '';
      final href = _tag(inner, 'href');
      if (href == null || href.isEmpty) continue;
      Uri url;
      try {
        url = Uri.parse(_unescape(href));
        if (!url.hasScheme) url = requestUri.resolveUri(url);
      } catch (_) {
        continue;
      }
      final path = url.path.endsWith('/') ? url.path : '${url.path}/';
      if (path == requestedPath) continue; // the collection itself
      final isDir = RegExp(r'<(?:[\w-]+:)?collection\b', caseSensitive: false).hasMatch(inner);
      final size = int.tryParse(_tag(inner, 'getcontentlength') ?? '') ?? 0;
      final display = _unescape(_tag(inner, 'displayname') ?? '').trim();
      final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
      final name = display.isNotEmpty
          ? display
          : (segments.isEmpty ? url.path : segments.last);
      if (name.isEmpty) continue;
      entries.add(DavEntry(
        url: url,
        name: name,
        isDir: isDir,
        size: size,
        modified: _parseDate(_tag(inner, 'getlastmodified')),
      ));
    }
    return entries;
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return HttpDate.parse(raw);
    } catch (_) {
      return DateTime.tryParse(raw);
    }
  }

  static String? _tag(String xml, String name) {
    final m = RegExp('<(?:[\\w-]+:)?$name\\b[^>]*>([\\s\\S]*?)</(?:[\\w-]+:)?$name>', caseSensitive: false).firstMatch(xml);
    return m?.group(1)?.trim();
  }

  static String _unescape(String s) => s
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}
