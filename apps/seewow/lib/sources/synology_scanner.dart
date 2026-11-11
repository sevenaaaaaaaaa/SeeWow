import 'dart:convert';

import '../domain/media_item.dart';
import 'json_api.dart';
import 'remote_files.dart';

class SynologyScanner {
  SynologyScanner(this.source, this.password)
    : api = JsonApi(Uri.parse(source.location));
  final MediaSource source;
  final String password;
  final JsonApi api;
  String? _sid;
  Future<Map<String, dynamic>> _data(
    String path,
    Map<String, String> params,
  ) async {
    final response = await api.form(path, params);
    if (response['success'] != true) {
      final code = (response['error'] as Map?)?['code'];
      throw FormatException(
        '群晖 API 错误（$code）。检查账号与 File Station 权限；需二步验证的账号可改用 SMB / WebDAV。',
      );
    }
    if (response['data'] is! Map<String, dynamic>)
      throw const FormatException('群晖响应格式无效');
    return response['data'] as Map<String, dynamic>;
  }

  Future<void> login() async {
    if (source.username.isEmpty || password.isEmpty)
      throw const FormatException('请填写群晖用户名和密码');
    final data = await _data('webapi/auth.cgi', {
      'api': 'SYNO.API.Auth',
      'version': '6',
      'method': 'login',
      'account': source.username,
      'passwd': password,
      'session': 'FileStation',
      'format': 'sid',
    });
    _sid = data['sid'] as String?;
    if (_sid == null || _sid!.isEmpty)
      throw const FormatException('群晖没有返回有效会话');
  }

  Future<List<MediaItem>> scan() async {
    await login();
    final items = <MediaItem>[];
    final queue = <(String, int)>[(normalizedRemotePath(source.rootPath), 0)];
    final visited = <String>{};
    try {
      while (queue.isNotEmpty) {
        final (folder, depth) = queue.removeLast();
        if (!visited.add(folder)) continue;
        if (depth > 16 || visited.length > 2000)
          throw const FormatException('群晖目录范围过大，请缩小根目录');
        var offset = 0;
        final paths = <String>{};
        for (var page = 0; page < 1000; page++) {
          final method = folder == '/' ? 'list_share' : 'list';
          final data = await _data('webapi/entry.cgi', {
            'api': 'SYNO.FileStation.List',
            'version': '2',
            'method': method,
            '_sid': _sid!,
            if (method == 'list') 'folder_path': folder,
            'offset': '$offset',
            'limit': '200',
            'additional': jsonEncode(['size', 'time']),
          });
          final list = data[method == 'list_share' ? 'shares' : 'files'];
          if (list is! List) throw const FormatException('群晖未返回文件列表');
          final total = (data['total'] as num?)?.toInt();
          if (list.isEmpty && total != null && offset < total)
            throw const FormatException('群晖分页中断；原片库保留');
          for (final raw in list.whereType<Map>()) {
            final path = normalizedRemotePath(raw['path'] as String? ?? '');
            final name = raw['name'] as String? ?? '';
            if (!paths.add(path) ||
                path == folder ||
                !path.startsWith(folder == '/' ? '/' : '$folder/'))
              throw const FormatException('群晖返回了无效或重复路径');
            if (raw['isdir'] == true)
              queue.add((path, depth + 1));
            else if (isVideoFile(name))
              items.add(
                remoteVideo(
                  source,
                  path,
                  name,
                  size: ((raw['additional'] as Map?)?['size'] as num? ?? 0)
                      .toInt(),
                ),
              );
            if (items.length > 20000)
              throw const FormatException('群晖超过 20,000 部影片，请缩小根目录');
          }
          offset += list.length;
          if (list.isEmpty ||
              total != null && offset >= total ||
              total == null && list.length < 200)
            break;
          if (page == 999) throw const FormatException('群晖分页超限；原片库保留');
        }
      }
      return items;
    } finally {
      try {
        await api.form('webapi/auth.cgi', {
          'api': 'SYNO.API.Auth',
          'version': '6',
          'method': 'logout',
          'session': 'FileStation',
          '_sid': _sid!,
        });
      } catch (_) {}
    }
  }

  Future<MediaItem> prepare(MediaItem item) async {
    await login();
    if (item.sourceRef == null) throw const FormatException('群晖文件引用缺失，请重新扫描');
    return item.copyWith(
      locator: api.uri('webapi/entry.cgi', {
        'api': 'SYNO.FileStation.Download',
        'version': '2',
        'method': 'download',
        'path': jsonEncode([item.sourceRef!]),
        'mode': 'open',
        '_sid': _sid!,
      }).toString(),
      httpHeaders: const {},
    );
  }

  void close() => api.close();
}
