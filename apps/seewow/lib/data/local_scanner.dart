import 'dart:io';

import 'package:crypto/crypto.dart';

import 'dart:convert';

import '../domain/filename_parser.dart';
import '../domain/media_item.dart';
import '../metadata/nfo_reader.dart';

class LocalScanner {
  static const _videoExt = {
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

  Future<List<MediaItem>> scan(MediaSource source) async {
    final root = Directory(source.location);
    if (!await root.exists())
      throw FileSystemException('文件夹不存在或未挂载', source.location);
    final results = <MediaItem>[];
    final files = <File>[];
    final dirs = <Directory>[root];
    while (dirs.isNotEmpty) {
      final dir = dirs.removeLast();
      try {
        for (final entry in await dir.list(followLinks: false).toList()) {
          if (entry is Directory)
            dirs.add(entry);
          else if (entry is File)
            files.add(entry);
        }
      } on FileSystemException {
        // A protected or disconnected subfolder must not abort the scan.
        continue;
      }
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final entity in files) {
      try {
        final name = entity.uri.pathSegments.last;
        if (name.startsWith('.')) continue;
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        final ext = name.substring(dot + 1).toLowerCase();
        if (!_videoExt.contains(ext)) continue;
        if (name.toLowerCase().contains('sample')) continue;
        final parent = entity.parent;
        final segs = parent.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .toList();
        final parentName = segs.isEmpty ? '' : segs.last;
        final parsed = FilenameParser.parse(
          name,
          parentFolder: parsedShowFolder(parentName) ? parentName : null,
        );
        final isEpisode = parsed.season != null && parsed.episode != null;
        // Artwork lives one level up for episodes: Show/poster.jpg, Show/fanart.jpg.
        final artDir =
            isEpisode &&
                parsedShowFolder(parentName) &&
                parent.parent.path != root.path
            ? parent.parent
            : parent;
        final poster =
            await _findArt(parent, [
              '${name.substring(0, dot)}-poster.jpg',
              '${name.substring(0, dot)}-poster.png',
            ]) ??
            await _findArt(artDir, const [
              'poster.jpg',
              'folder.jpg',
              'cover.jpg',
              'poster.png',
            ]) ??
            await _findArt(parent, const [
              'poster.jpg',
              'folder.jpg',
              'cover.jpg',
              'poster.png',
            ]);
        final fanart =
            await _findArt(parent, [
              '${name.substring(0, dot)}-fanart.jpg',
              '${name.substring(0, dot)}-fanart.png',
            ]) ??
            await _findArt(artDir, const [
              'fanart.jpg',
              'backdrop.jpg',
              'fanart.png',
            ]) ??
            await _findArt(parent, const [
              'fanart.jpg',
              'backdrop.jpg',
              'fanart.png',
            ]);
        final stat = await entity.stat();
        final id = sha1
            .convert(utf8.encode(entity.path))
            .toString()
            .substring(0, 20);
        final showTitle = isEpisode
            ? (parsed.showTitle ?? _cleanFolder(artDir.path))
            : null;
        final title = isEpisode
            ? (parsed.episode != null ? '第 ${parsed.episode} 集' : parsed.title)
            : parsed.title;
        final nfo = await NfoInfo.read([
          File('${entity.path.substring(0, entity.path.lastIndexOf('.'))}.nfo'),
          if (!isEpisode) File('${parent.path}/movie.nfo'),
        ]);
        final showNfo = isEpisode
            ? await NfoInfo.read([
                File('${artDir.path}/tvshow.nfo'),
                File('${parent.parent.path}/tvshow.nfo'),
              ])
            : null;
        final demo = source.name.contains('演示')
            ? _demoMeta[_normalize(isEpisode ? (showTitle ?? '') : title)]
            : null;
        results.add(
          MediaItem(
            id: id,
            sourceId: source.id,
            aiAllowed: source.providerId != 'telegramLocal',
            metadata: (nfo ?? showNfo)?.asMetadata(
              fallbackTitle: title,
              mediaType: isEpisode ? 'episode' : 'movie',
              inherit: showNfo,
            ),
            kind: isEpisode ? MediaKind.episode : MediaKind.movie,
            title: nfo?.title ?? title,
            locator: entity.path,
            showTitle: showNfo?.title ?? nfo?.showTitle ?? showTitle,
            season: nfo?.season ?? parsed.season,
            episode: nfo?.episode ?? parsed.episode,
            year: nfo?.year ?? showNfo?.year ?? parsed.year ?? demo?.year,
            quality: parsed.quality,
            posterUrl:
                poster?.path ??
                NfoInfo.artwork(
                  nfo?.poster ?? showNfo?.poster,
                  (nfo?.poster != null ? nfo?.directory : showNfo?.directory) ??
                      parent.uri,
                ),
            backdropUrl:
                fanart?.path ??
                NfoInfo.artwork(
                  nfo?.backdrop ?? showNfo?.backdrop,
                  (nfo?.backdrop != null
                          ? nfo?.directory
                          : showNfo?.directory) ??
                      parent.uri,
                ) ??
                poster?.path,
            addedAt: stat.modified,
            fileSize: stat.size,
            container: ext.toUpperCase(),
            rating: nfo?.rating ?? showNfo?.rating ?? demo?.rating,
            genres: nfo?.genres.isNotEmpty == true
                ? nfo!.genres
                : showNfo?.genres.isNotEmpty == true
                ? showNfo!.genres
                : demo?.genres ?? const [],
            overview: nfo?.overview.isNotEmpty == true
                ? nfo!.overview
                : showNfo?.overview.isNotEmpty == true
                ? showNfo!.overview
                : demo?.overview ?? '',
            duration: nfo != null && nfo.duration > 0
                ? nfo.duration
                : demo?.duration ?? 0,
            position: demo == null
                ? 0
                : isEpisode
                ? (_normalize(showTitle ?? '') == 'dark'
                      ? demo.duration * 0.42
                      : 0)
                : (_normalize(title) == 'dune part two'
                      ? demo.duration * 0.18
                      : 0),
          ),
        );
      } on FileSystemException {
        // Unreadable files are skipped; the rest of the folder remains usable.
      }
    }
    results.sort(
      (a, b) =>
          (b.addedAt ?? DateTime(1970)).compareTo(a.addedAt ?? DateTime(1970)),
    );
    return results;
  }

  bool parsedShowFolder(String name) {
    final l = name.toLowerCase();
    return l.contains('season') ||
        l.contains('s0') ||
        l.contains('第') ||
        RegExp(r'^s\d+').hasMatch(l);
  }

  Future<File?> _findArt(Directory dir, List<String> names) async {
    for (final n in names) {
      final f = File('${dir.path}/$n');
      if (await f.exists()) return f;
    }
    return null;
  }
}

class _DemoMeta {
  const _DemoMeta(
    this.rating,
    this.genres,
    this.overview,
    this.duration,
    this.year,
  );
  final double rating;
  final List<String> genres;
  final String overview;
  final double duration;
  final int year;
}

String _cleanFolder(String path) {
  final seg = path.split('/').where((s) => s.isNotEmpty).toList();
  if (seg.isEmpty) return '';
  return seg.last.replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '').trim();
}

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

const _demoMeta = <String, _DemoMeta>{
  'the grand budapest hotel': _DemoMeta(
    8.1,
    ['喜剧', '剧情', '冒险'],
    '传奇门房古斯塔夫与门童零，在一座虚构的欧洲大饭店里卷入遗产争夺、名画失窃与一段优雅又荒诞的旧日传奇。',
    5940,
    2014,
  ),
  'interstellar': _DemoMeta(
    8.7,
    ['科幻', '冒险', '剧情'],
    '地球濒临枯竭，前宇航员库珀穿越虫洞寻找人类新家园，在时间与引力之间押上全部亲情。',
    10140,
    2014,
  ),
  'blade runner 2049': _DemoMeta(
    8.0,
    ['科幻', '悬疑', '剧情'],
    '复制人警探 K 追查一具旧型号遗骸，揭开一个足以撕裂人类与复制人秩序的秘密。',
    9840,
    2017,
  ),
  'dune part two': _DemoMeta(
    8.5,
    ['科幻', '冒险'],
    '保罗·厄崔迪与弗雷曼人并肩作战，在沙丘星球上向摧毁他家族的阴谋者展开复仇。权力、预言与牺牲在无尽的黄沙中交织。',
    9960,
    2024,
  ),
  'dark': _DemoMeta(
    8.8,
    ['悬疑', '科幻', '剧情'],
    '一个孩子的失踪撕开了小镇温登的四代秘密。洞穴深处的时空隧道将过去、现在与未来缠成同一个结。',
    3000,
    2017,
  ),
  'severance': _DemoMeta(
    8.7,
    ['悬疑', '科幻', '剧情'],
    '卢蒙公司的员工接受「分离手术」，工作与生活记忆被彻底切开，直到裂缝从内部生长出来。',
    3120,
    2022,
  ),
};
