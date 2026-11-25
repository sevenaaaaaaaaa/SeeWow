import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/playback/chapters.dart';
import 'package:seewow/playback/chapters_sources.dart';
import 'package:seewow/playback/film_rail.dart';

/// 章节轨的数据源。三条要在测试里钉死：
/// 1) ffprobe 的 JSON 能解析成模型（含中文标题、字符串时间）；
/// 2) mpv 的 chapter-list 只有起点，终点要按"下一章起点/片尾"推出来；
/// 3) 落盘缓存能往返，且源文件一变就失效。

const _ffprobeSample = '''
{
  "chapters": [
    {"id": 1, "start_time": "0.000000", "end_time": "8.000000", "tags": {"title": "开场"}},
    {"id": 2, "start_time": "8.000000", "end_time": "16.000000", "tags": {"title": "第一次转折"}},
    {"id": 3, "start_time": "16.000000", "end_time": "24.000000"}
  ]
}''';

MediaItem _item(String locator, {double duration = 24}) => MediaItem(
  id: 'demo',
  sourceId: 'local',
  kind: MediaKind.movie,
  title: 'Demo',
  locator: locator,
  duration: duration,
);

void main() {
  group('ffprobe 解析', () {
    test('三个章节，中文标题与字符串时间都要认', () {
      final chapters = parseFfprobeChapters(_ffprobeSample);
      expect(chapters.length, 3);
      expect(chapters[0].start, 0);
      expect(chapters[0].end, 8);
      expect(chapters[0].title, '开场');
      expect(chapters[1].title, '第一次转折');
      // 没有 tags 的章节标题是空串，不是 null，也不是"未命名"这种编出来的字
      expect(chapters[2].title, '');
      expect(chapters[2].span, 8);
    });

    test('空表、乱码、缺字段：一律空表，不抛', () {
      expect(parseFfprobeChapters('{"chapters": []}'), isEmpty);
      expect(parseFfprobeChapters('not json'), isEmpty);
      expect(parseFfprobeChapters(''), isEmpty);
      expect(
        parseFfprobeChapters('{"chapters":[{"start_time":"5"}]}'),
        isEmpty,
      );
      // 终点早于起点的是坏数据，直接丢
      expect(
        parseFfprobeChapters(
          '{"chapters":[{"start_time":"9","end_time":"3"}]}',
        ),
        isEmpty,
      );
    });

    test('数字形式的秒也收', () {
      final chapters = parseFfprobeChapters(
        '{"chapters":[{"start_time":0,"end_time":12.5,"tags":{"title":"x"}}]}',
      );
      expect(chapters.single.end, 12.5);
    });
  });

  group('mpv 解析', () {
    test('只有起点：终点取下一章起点，最后一章到片尾', () {
      final chapters = parseMpvChapters(
        '[{"title":"开场","time":0},{"title":"转折","time":300},{"title":"收尾","time":900}]',
        duration: 1200,
      );
      expect(chapters.length, 3);
      expect(chapters[0].end, 300);
      expect(chapters[1].end, 900);
      expect(chapters[2].end, 1200);
    });

    test('乱序会先排序；空/坏数据返回空表', () {
      final chapters = parseMpvChapters(
        '[{"time":900},{"time":0}]',
        duration: 1000,
      );
      expect(chapters.first.start, 0);
      expect(chapters.first.end, 900);
      expect(parseMpvChapters(null, duration: 10), isEmpty);
      expect(parseMpvChapters('[]', duration: 10), isEmpty);
      expect(parseMpvChapters('oops', duration: 10), isEmpty);
    });

    test('片长未知时最后一章不越界', () {
      final chapters = parseMpvChapters(
        '[{"time":10},{"time":20}]',
        duration: 0,
      );
      expect(chapters.last.end, 20);
    });
  });

  test('章节 → 轨上的长线：区间与标题都带上', () {
    final marks = chapterMarks(const [
      Chapter(start: 0, end: 60, title: '开场'),
      Chapter(start: 60, end: 180, title: '中段'),
    ]);
    expect(marks.length, 2);
    expect(marks.first.kind, RailMarkKind.chapter);
    expect(marks.first.seconds, 0);
    expect(marks.first.endSeconds, 60);
    expect(marks.first.label, '开场');
  });

  group('落盘', () {
    late Directory root;
    late ChapterStore store;

    setUp(() {
      root = Directory.systemTemp.createTempSync('chapters-test');
      store = ChapterStore(directory: root);
    });
    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('写进去读出来一模一样', () async {
      final item = _item('test/fixtures/chapters.mkv');
      await store.write(item, const [
        Chapter(start: 0, end: 3, title: '开场'),
        Chapter(start: 3, end: 6, title: '雨夜'),
      ]);
      final back = await store.read(item);
      expect(back, isNotNull);
      expect(back!.length, 2);
      expect(back[1].title, '雨夜');
      expect(back[1].start, 3);
    });

    test('源文件变了缓存失效', () async {
      final file = File('test/fixtures/chapters.mkv');
      final item = _item(file.path);
      await store.write(item, const [Chapter(start: 0, end: 3, title: 'x')]);
      expect(await store.read(item), isNotNull);

      // 同一个定位符、体积变了：旧目录必须判过期
      final copy = File('${root.path}/copy.mkv')
        ..writeAsBytesSync(List<int>.filled(4096, 1));
      final other = _item(copy.path);
      await store.write(other, const [Chapter(start: 0, end: 3, title: 'x')]);
      copy.writeAsBytesSync(List<int>.filled(8192, 1));
      expect(await store.read(other), isNull);
    });

    test('缓存文件损坏当成没有', () async {
      final item = _item('test/fixtures/chapters.mkv');
      await store.write(item, const [Chapter(start: 0, end: 3, title: 'x')]);
      final file = File('${root.path}/${store.keyFor(item)}.json');
      file.writeAsStringSync('{ broken');
      expect(await store.read(item), isNull);
    });
  });

  test('端到端：真的跑一次 ffprobe，拿到 4 章中文标题', () async {
    final ready = await FfprobeChapterSource.available();
    // ignore: avoid_print
    print('[chapters] ffprobe available: $ready');
    if (!ready) {
      // 没有 ffprobe 的机器（CI）跳过；这一行打印是留给日志的证据，
      // 否则"跳过"和"通过"在输出里长得一样。
      return;
    }
    final file = File('test/fixtures/chapters.mkv');
    expect(file.existsSync(), isTrue, reason: 'fixture 必须存在');

    final chapters = await const FfprobeChapterSource().read(
      _item(file.path, duration: 12),
    );
    expect(chapters.length, 4);
    expect(chapters.map((c) => c.title).toList(), [
      '开场',
      '第一次转折',
      '雨夜',
      '收尾',
    ]);
    expect(chapters[1].start, closeTo(3, 0.01));
    expect(chapters[1].end, closeTo(6, 0.01));
  });

  test('缓存命中时不再去问 ffprobe', () async {
    final root = Directory.systemTemp.createTempSync('chapters-hit');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = ChapterStore(directory: root);
    final item = _item('test/fixtures/chapters.mkv', duration: 12);
    await store.write(item, const [Chapter(start: 0, end: 12, title: '整段')]);

    final load = await loadChapters(item, store: store, allowFfprobe: false);
    expect(load.source, 'cache');
    expect(load.chapters.single.title, '整段');
  });

  test('什么都没有时返回 none，而不是编出章节', () async {
    final root = Directory.systemTemp.createTempSync('chapters-none');
    addTearDown(() => root.deleteSync(recursive: true));
    final load = await loadChapters(
      _item('test/fixtures/chapters.mkv', duration: 12),
      store: ChapterStore(directory: root),
      allowFfprobe: false,
    );
    expect(load.source, 'none');
    expect(load.isEmpty, isTrue);
  });
}
