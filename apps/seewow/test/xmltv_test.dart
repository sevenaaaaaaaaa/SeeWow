import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/xmltv.dart';

void main() {
  test('parses programmes with offsets and entities', () {
    const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="cctv1"><display-name>CCTV 1</display-name></channel>
  <programme start="20261105120000 +0800" stop="20261105133000 +0800" channel="cctv1">
    <title lang="zh">新闻 &amp; 联播</title>
    <desc>每日 <b>要闻</b></desc>
  </programme>
  <programme start="20261105133000 +0800" stop="20261105150000 +0800" channel="cctv1">
    <title>电视剧场</title>
    <sub-title>第 3 集</sub-title>
  </programme>
  <programme start="20261105100000 +0800" stop="20261105110000 +0800" channel="empty-title"></programme>
</tv>
''';
    final list = XMLTVParser.parse(xml);
    expect(list.length, 2);
    expect(list.first.channelId, 'cctv1');
    expect(list.first.title, '新闻 & 联播');
    expect(list.first.description, '每日 要闻');
    expect(list.first.start.hour, 12);
    expect(list.first.stop.hour, 13);
    expect(list.first.stop.minute, 30);
    expect(list[1].subtitle, '第 3 集');
  });

  test('groups by channel and drops old programmes', () {
    final now = DateTime.now();
    String stamp(DateTime t) =>
        t.year.toString().padLeft(4, '0') +
        t.month.toString().padLeft(2, '0') +
        t.day.toString().padLeft(2, '0') +
        t.hour.toString().padLeft(2, '0') +
        t.minute.toString().padLeft(2, '0') +
        '00';
    final xml = '''
<tv>
  <programme start="${stamp(now.subtract(const Duration(days: 2)))} +0800" stop="${stamp(now.subtract(const Duration(days: 1)))} +0800" channel="old"><title>旧节目</title></programme>
  <programme start="${stamp(now.subtract(const Duration(minutes: 30)))} +0800" stop="${stamp(now.add(const Duration(minutes: 30)))} +0800" channel="now"><title>正在播</title></programme>
</tv>
''';
    final grouped = XMLTVParser.group(XMLTVParser.parse(xml));
    expect(grouped.containsKey('old'), isFalse);
    expect(grouped['now']!.single.title, '正在播');
    final show = grouped['now']!.single;
    expect(show.progressAt(now), greaterThan(0.4));
    expect(show.progressAt(now), lessThan(0.6));
  });
}
