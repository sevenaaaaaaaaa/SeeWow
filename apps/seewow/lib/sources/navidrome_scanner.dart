import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../domain/media_item.dart';
import 'json_api.dart';

class NavidromeScanner {
  NavidromeScanner(this.source, this.password)
    : api = JsonApi(Uri.parse(source.location));
  final MediaSource source;
  final String password;
  final JsonApi api;
  Map<String, String> auth() {
    if (source.username.isEmpty || password.isEmpty)
      throw const FormatException('请填写 Navidrome 用户名和密码');
    final random = Random.secure();
    final salt = List.generate(
      16,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
    return {
      'u': source.username,
      't': md5.convert(utf8.encode(password + salt)).toString(),
      's': salt,
      'v': '1.16.1',
      'c': 'SeeWow',
      'f': 'json',
    };
  }

  Future<List<MediaItem>> scan() async {
    final items = <MediaItem>[];
    final seen = <String>{};
    for (var page = 0; page < 100; page++) {
      final raw = await api.get('rest/search3.view', {
        ...auth(),
        'query': '',
        'artistCount': '0',
        'albumCount': '0',
        'songCount': '200',
        'songOffset': '${items.length}',
      });
      final response = raw['subsonic-response'];
      if (response is! Map || response['status'] != 'ok')
        throw const FormatException('Navidrome 认证或目录请求失败，请检查账号、协议权限');
      final search = response['searchResult3'];
      if (search is! Map) throw const FormatException('Navidrome 未返回音乐目录');
      final list = search['song'] ?? [];
      if (list is! List) throw const FormatException('Navidrome 音乐列表格式无效');
      for (final m in list.whereType<Map>()) {
        final id = m['id']?.toString() ?? '';
        if (id.isEmpty || !seen.add(id))
          throw const FormatException('Navidrome 返回重复分页；原音乐库保留');
        items.add(
          MediaItem(
            id: '${source.id}:$id',
            sourceId: source.id,
            kind: MediaKind.audio,
            title: m['title'] as String? ?? '未命名曲目',
            artist: m['artist'] as String? ?? '',
            album: m['album'] as String? ?? '',
            locator: Uri(
              scheme: 'seewow',
              host: 'source',
              queryParameters: {'ref': id},
            ).toString(),
            sourceRef: id,
            duration: (m['duration'] as num? ?? 0).toDouble(),
            year: (m['year'] as num?)?.toInt(),
            genres: m['genre'] is String ? [m['genre'] as String] : const [],
            quality: m['bitRate'] == null ? '' : '${m['bitRate']} kbps',
            container: (m['suffix'] as String? ?? '').toUpperCase(),
            fileSize: (m['size'] as num? ?? 0).toInt(),
            overview: [m['artist'], m['album']].whereType<String>().join(' · '),
          ),
        );
      }
      if (list.length < 200) return items;
    }
    throw const FormatException('Navidrome 超过 20,000 首扫描上限；原音乐库保留');
  }

  MediaItem prepare(MediaItem item) {
    if (item.sourceRef == null) throw const FormatException('曲目引用缺失，请重新扫描');
    return item.copyWith(
      locator: api.uri('rest/stream.view', {
        ...auth(),
        'id': item.sourceRef!,
        'format': 'raw',
      }).toString(),
      httpHeaders: const {},
    );
  }

  void close() => api.close();
}
