import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/media_item.dart';
import 'film_rail.dart';

/// 章节。起止都以秒计；标题常常是空的——不少容器只给时间不给名。
class Chapter {
  const Chapter({required this.start, required this.end, this.title = ''});

  final double start;
  final double end;
  final String title;

  double get span => (end - start).clamp(0, double.infinity);

  Map<String, dynamic> toJson() => {'s': start, 'e': end, 't': title};

  static Chapter? fromJson(Map<String, dynamic> j) {
    final start = (j['s'] as num?)?.toDouble();
    final end = (j['e'] as num?)?.toDouble();
    if (start == null || end == null || !start.isFinite || !end.isFinite) {
      return null;
    }
    return Chapter(start: start, end: end, title: (j['t'] as String?) ?? '');
  }

  @override
  String toString() =>
      'Chapter(${start.toStringAsFixed(1)}—${end.toStringAsFixed(1)} '
      '${title.isEmpty ? '未命名' : title})';
}

/// 解析 ffprobe -show_chapters -of json 的输出。
///
/// ffprobe 把时间写成字符串（"8.000000"），偶尔写成数字；两种都收。
/// 解析失败或没有章节都返回空表——章节是锦上添花，坏了不该让播放页起不来。
List<Chapter> parseFfprobeChapters(String output) {
  try {
    final json = jsonDecode(output);
    if (json is! Map) return const [];
    final list = json['chapters'];
    if (list is! List) return const [];
    final chapters = <Chapter>[];
    for (final item in list) {
      if (item is! Map) continue;
      final start = _seconds(item['start_time']);
      final end = _seconds(item['end_time']);
      if (start == null || end == null || end <= start) continue;
      final tags = item['tags'];
      final title = tags is Map ? (tags['title'] as String? ?? '') : '';
      chapters.add(Chapter(start: start, end: end, title: title));
    }
    chapters.sort((x, y) => x.start.compareTo(y.start));
    return chapters;
  } catch (_) {
    return const [];
  }
}

double? _seconds(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// 解析 mpv 的 chapter-list 属性。
///
/// 它只给起点（time 字段）和标题，没有终点：第 n 章的结束就是第 n+1 章的开始，
/// 最后一章到片尾。这是容器的真实语义，不是我们编的。
List<Chapter> parseMpvChapters(String? raw, {required double duration}) {
  if (raw == null || raw.trim().isEmpty) return const [];
  try {
    final list = jsonDecode(raw);
    if (list is! List) return const [];
    final starts = <({double time, String title})>[];
    for (final item in list) {
      if (item is! Map) continue;
      final time = (item['time'] as num?)?.toDouble();
      if (time == null || !time.isFinite) continue;
      starts.add((time: time, title: (item['title'] as String?) ?? ''));
    }
    if (starts.isEmpty) return const [];
    starts.sort((x, y) => x.time.compareTo(y.time));
    final last = duration > 0 ? duration : starts.last.time;
    final chapters = <Chapter>[];
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i].time;
      final end = i + 1 < starts.length ? starts[i + 1].time : last;
      if (end <= start) continue;
      chapters.add(Chapter(start: start, end: end, title: starts[i].title));
    }
    return chapters;
  } catch (_) {
    return const [];
  }
}

/// 章节 → 轨上的灰色长线。数据为空就是空表，轨上什么都不画。
List<RailMark> chapterMarks(List<Chapter> chapters) => [
  for (final chapter in chapters)
    RailMark(
      seconds: chapter.start,
      endSeconds: chapter.end,
      kind: RailMarkKind.chapter,
      label: chapter.title,
    ),
];

/// 章节落盘：一本片的目录不会变，读一次存下来，之后每个页面都不必再解析容器。
///
/// 布局：支持目录/SeeWow/chapters/条目号.json，原子写（.tmp 改名）。
/// 与 trickplay 同一套约定，但目录分开：章节是几百字节，缩略图是几兆，
/// 混在一起清理时只会互相误伤。
class ChapterStore {
  ChapterStore({this.directory});

  static final ChapterStore I = ChapterStore();
  static const int format = 1;

  final Directory? directory;

  Future<Directory> _root() async {
    final dir =
        directory ??
        Directory(
          '${(await getApplicationSupportDirectory()).path}/SeeWow/chapters',
        );
    await dir.create(recursive: true);
    return dir;
  }

  String keyFor(MediaItem item) => sha256
      .convert(utf8.encode('${item.id}|${item.locator}'))
      .toString()
      .substring(0, 16);

  Future<File> _file(String key) async {
    if (!RegExp(r'^[a-f0-9]{16}$').hasMatch(key)) {
      throw const FormatException('章节标识无效');
    }
    return File('${(await _root()).path}/$key.json');
  }

  /// 读缓存。没有、损坏、格式版本不符、源文件变了，一律返回 null（当作要重新取）。
  Future<List<Chapter>?> read(MediaItem item) async {
    try {
      final file = await _file(keyFor(item));
      if (!await file.exists()) return null;
      if (await file.length() > 512 * 1024) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map || json['v'] != format) return null;
      final stat = await sourceStat(item);
      if (stat.size != 0 &&
          (json['size'] as int? ?? 0) != 0 &&
          json['size'] != stat.size) {
        return null;
      }
      if (stat.mtimeMs != 0 &&
          (json['mtime'] as int? ?? 0) != 0 &&
          json['mtime'] != stat.mtimeMs) {
        return null;
      }
      final list = json['chapters'];
      if (list is! List) return null;
      final chapters = <Chapter>[];
      for (final row in list) {
        if (row is! Map) continue;
        final chapter = Chapter.fromJson(Map<String, dynamic>.from(row));
        if (chapter != null) chapters.add(chapter);
      }
      return chapters;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(MediaItem item, List<Chapter> chapters) async {
    final stat = await sourceStat(item);
    final file = await _file(keyFor(item));
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'v': format,
        'size': stat.size,
        'mtime': stat.mtimeMs,
        'chapters': [for (final c in chapters) c.toJson()],
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }

  Future<void> clear(MediaItem item) async {
    final file = await _file(keyFor(item));
    if (await file.exists()) await file.delete();
  }
}

/// 源文件的体积与修改时间。远端流或文件不存在时给 (0, 0)，表示不参与判定。
Future<({int size, int mtimeMs})> sourceStat(MediaItem item) async {
  try {
    final uri = Uri.tryParse(item.locator);
    if (uri != null && ['http', 'https'].contains(uri.scheme)) {
      return (size: item.fileSize, mtimeMs: 0);
    }
    final file = File(item.locator);
    if (!await file.exists()) return (size: 0, mtimeMs: 0);
    final stat = await file.stat();
    return (size: stat.size, mtimeMs: stat.modified.millisecondsSinceEpoch);
  } catch (_) {
    return (size: 0, mtimeMs: 0);
  }
}
