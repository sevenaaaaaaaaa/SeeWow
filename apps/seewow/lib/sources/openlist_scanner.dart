import 'dart:io';

import '../domain/media_item.dart';
import 'json_api.dart';
import 'remote_files.dart';

class OpenListScanner {
  OpenListScanner(this.source, String token)
    : api = JsonApi(
        Uri.parse(source.location),
        headers: token.trim().isEmpty
            ? const {}
            : {'Authorization': token.trim()},
      );
  final MediaSource source;
  final JsonApi api;
  Future<Map<String, dynamic>> _call(String method, String path) async {
    final response = await api.post('api/fs/$method', {
      'path': path,
      'password': '',
      'refresh': false,
    });
    return data(response);
  }

  static Map<String, dynamic> data(Map<String, dynamic> response) {
    if (response['code'] != 200)
      throw FormatException('网关请求失败（${response['code']}），请检查 Token、挂载状态与目录权限');
    if (response['data'] is! Map<String, dynamic>)
      throw const FormatException('网关返回格式无效');
    return response['data'] as Map<String, dynamic>;
  }

  Future<List<MediaItem>> scan() async {
    final items = <MediaItem>[];
    final queue = <(String, int)>[(normalizedRemotePath(source.rootPath), 0)];
    final visited = <String>{};
    while (queue.isNotEmpty) {
      final (path, depth) = queue.removeLast();
      if (!visited.add(path)) continue;
      if (depth > 16 || visited.length > 2000)
        throw const FormatException('目录范围过大，请缩小根目录；原片库保留');
      var offset = 0;
      final names = <String>{};
      for (var page = 1; page <= 1000; page++) {
        final json = data(
          await api.post('api/fs/list', {
            'path': path,
            'password': '',
            'page': page,
            'per_page': 200,
            'refresh': false,
          }),
        );
        final content = json['content'];
        final total = (json['total'] as num?)?.toInt();
        if (content == null && total == 0) break;
        if (content is! List) throw const FormatException('网关未返回目录列表');
        if (content.isEmpty && total != null && offset < total)
          throw const FormatException('网关分页中断；原片库保留');
        for (final raw in content) {
          if (raw is! Map || raw['name'] is! String)
            throw const FormatException('网关文件格式无效');
          final name = raw['name'] as String;
          if (!names.add(name)) throw const FormatException('网关返回重复分页；原片库保留');
          final child = childRemotePath(path, name);
          if (name.startsWith('.')) continue;
          if (raw['is_dir'] == true) {
            queue.add((child, depth + 1));
          } else if (isVideoFile(name)) {
            items.add(
              remoteVideo(
                source,
                child,
                name,
                size: (raw['size'] as num? ?? 0).toInt(),
                modified: DateTime.tryParse(raw['modified'] as String? ?? ''),
              ),
            );
          }
          if (items.length > 20000)
            throw const FormatException('超过 20,000 个影片，请缩小根目录；原片库保留');
        }
        offset += content.length;
        if (content.isEmpty ||
            (total != null && offset >= total) ||
            (total == null && content.length < 200))
          break;
        if (page == 1000) throw const FormatException('网关分页超限；原片库保留');
      }
    }
    return items;
  }

  Future<MediaItem> prepare(MediaItem item) async {
    final ref = item.sourceRef;
    if (ref == null) throw const FormatException('缺少网关文件引用，请重新扫描');
    final json = await _call('get', normalizedRemotePath(ref));
    final url = playableUri(json['raw_url'] as String? ?? '');
    // Gateway authorization never follows the direct URL to a cloud host.
    final headers = <String, String>{
      if (url.origin == api.base.origin) ...api.headers,
    };
    final explicitHeaders = json['headers'];
    if (explicitHeaders is Map) {
      for (final e in explicitHeaders.entries) {
        if ([
              'user-agent',
              'referer',
              'origin',
              'cookie',
              'authorization',
            ].contains(e.key.toString().toLowerCase()) &&
            e.value is String)
          headers[e.key.toString()] = e.value as String;
      }
    }
    if (url.origin == api.base.origin && headers.isNotEmpty) {
      final resolved = await _resolveGatewayRedirects(url, headers);
      return item.copyWith(
        locator: resolved.$1.toString(),
        httpHeaders: resolved.$2,
      );
    }
    return item.copyWith(locator: url.toString(), httpHeaders: headers);
  }

  Future<(Uri, Map<String, String>)> _resolveGatewayRedirects(
    Uri initial,
    Map<String, String> initialHeaders,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12);
    var current = initial;
    var headers = {...initialHeaders};
    try {
      for (var hop = 0; hop < 6; hop++) {
        final req = await client
            .getUrl(current)
            .timeout(const Duration(seconds: 15));
        req.followRedirects = false;
        headers.forEach(req.headers.set);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        final response = await req.close().timeout(const Duration(seconds: 20));
        if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null) throw const FormatException('网关跳转缺少目标地址');
          final next = playableUri(current.resolve(location).toString());
          if (next.origin != current.origin)
            headers.removeWhere(
              (name, _) => [
                'authorization',
                'cookie',
                'proxy-authorization',
                'x-api-key',
              ].contains(name.toLowerCase()),
            );
          current = next;
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 206)
          throw const FormatException('网关播放地址无法读取，请检查挂载状态');
        return (current, headers);
      }
      throw const FormatException('网关播放跳转次数过多');
    } finally {
      client.close(force: true);
    }
  }

  void close() => api.close();
}
