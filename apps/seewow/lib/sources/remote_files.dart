import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/filename_parser.dart';
import '../domain/media_item.dart';

const videoExtensions = {
  'mp4',
  'mkv',
  'mov',
  'm4v',
  'avi',
  'ts',
  'm2ts',
  'mts',
  'webm',
  'wmv',
  'flv',
  'rmvb',
  'rm',
  'ogv',
  'mpg',
  'mpeg',
  'vob',
  '3gp',
};
bool isVideoFile(String name) =>
    videoExtensions.contains(name.split('.').last.toLowerCase());
String normalizedRemotePath(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty && s != '.')
      .toList();
  if (parts.contains('..')) throw const FormatException('目录不能包含上级路径');
  return '/${parts.join('/')}';
}

String childRemotePath(String parent, String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains('\\'))
    throw const FormatException('服务返回了无效的文件名');
  return normalizedRemotePath('$parent/$name');
}

MediaItem remoteVideo(
  MediaSource source,
  String path,
  String name, {
  int size = 0,
  DateTime? modified,
}) {
  final p = FilenameParser.parse(name);
  return MediaItem(
    id: '${source.id}:${sha1.convert(utf8.encode(path))}',
    sourceId: source.id,
    kind: p.episode == null ? MediaKind.movie : MediaKind.episode,
    title: p.episode == null ? p.title : '第 ${p.episode} 集',
    showTitle: p.showTitle,
    season: p.season,
    episode: p.episode,
    year: p.year,
    quality: p.quality,
    container: name.split('.').last.toUpperCase(),
    fileSize: size,
    addedAt: modified,
    locator: Uri(
      scheme: 'seewow',
      host: 'source',
      path: '/${source.id}',
      queryParameters: {'ref': path},
    ).toString(),
    sourceRef: path,
  );
}

Uri playableUri(String url) {
  final u = Uri.tryParse(url);
  if (u == null ||
      !['http', 'https'].contains(u.scheme) ||
      u.host.isEmpty ||
      u.userInfo.isNotEmpty)
    throw const FormatException('服务未返回有效的 HTTP 播放地址');
  return u;
}
