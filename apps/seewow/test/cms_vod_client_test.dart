import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/sources/cms_vod_client.dart';

/// 返回体结构取自苹果CMS v10 的 ac=videolist / ac=list 两种形态（JSON 与 XML）。
const jsonBody = '''
{"code":1,"msg":"数据列表","page":1,"pagecount":100,"limit":"20","total":2,
"list":[
 {"vod_id":3365,"vod_name":"测试用片","vod_pic":"https://img.test/a.jpg","vod_remarks":"更新至02集",
  "vod_year":"2024","vod_area":"大陆","vod_lang":"国语","type_name":"动作片",
  "vod_actor":"甲,乙","vod_director":"丙","vod_content":"简介文字",
  "vod_play_from":"lzm3u8","vod_play_url":""},
 {"vod_id":3366,"vod_name":"第二部","type_name":"剧情片","vod_play_from":"lzm3u8\u0024\u0024\u0024ffm3u8",
  "vod_play_url":"第01集\u0024https://a.test/1/index.m3u8#第02集\u0024https://a.test/2/index.m3u8\u0024\u0024\u0024正片\u0024https://b.test/full.mp4"}
]}
''';

void main() {
  group('解析 JSON 返回', () {
    test('列表字段与线路拆分', () {
      final items = CmsVodClient.parseItems(jsonBody);
      expect(items.length, 2);
      final item = items.last;
      expect(item.name, '第二部');
      expect(item.id, '3366');
      expect(item.sources.length, 2);
      expect(item.sources.first.from, 'lzm3u8');
      expect(item.sources.first.episodes.length, 2);
      expect(item.sources.first.episodes.first.name, '第01集');
      expect(
        item.sources.first.episodes.first.url,
        'https://a.test/1/index.m3u8',
      );
      expect(item.sources.last.episodes.single.url, 'https://b.test/full.mp4');
      expect(item.hasPlayableSource, isTrue);
    });

    test('没有播放地址的条目不算可播', () {
      final items = CmsVodClient.parseItems(
        '{"list":[{"vod_id":1,"vod_name":"空","vod_play_url":""}]}',
      );
      expect(items.single.hasPlayableSource, isFalse);
    });

    test('没有 list 字段返回空，不抛错', () {
      expect(CmsVodClient.parseItems('{"code":0,"msg":"参数错误"}'), isEmpty);
    });
  });

  group('解析 XML 返回', () {
    test('rss/list/video 结构与 dd flag', () {
      const body = '''
<?xml version="1.0" encoding="utf-8"?>
<rss version="5.1"><list page="1" pagecount="1" pagesize="20" recordcount="1">
<video>
  <id>7</id><name>XML 片名</name><pic>https://img.test/x.jpg</pic>
  <type>科幻片</type><year>2023</year><area>美国</area><lang>英语</lang>
  <note>HD</note><actor>张三</actor><director>李四</director>
  <des><![CDATA[简介]]></des>
  <dl><dd flag="lzm3u8"><![CDATA[第01集\u0024https://c.test/1.m3u8#第02集\u0024https://c.test/2.m3u8]]></dd></dl>
</video>
</list></rss>
''';
      final items = CmsVodClient.parseItems(body);
      expect(items.single.name, 'XML 片名');
      expect(items.single.typeName, '科幻片');
      expect(items.single.sources.single.episodes.length, 2);
      expect(
        items.single.sources.single.episodes.last.url,
        'https://c.test/2.m3u8',
      );
    });
  });

  group('分类接口', () {
    test('JSON class 与 XML ty 都能读', () {
      final json = CmsVodClient.parseCategories(
        '{"class":[{"type_id":1,"type_name":"电影"},{"type_id":2,"type_name":"剧集"}]}',
      );
      expect(json.length, 2);
      expect(json.last.name, '剧集');
      final xml = CmsVodClient.parseCategories(
        '<rss><class><ty id="3">动漫</ty><ty id="4">综艺</ty></class></rss>',
      );
      expect(xml.map((c) => c.id), [3, 4]);
      expect(xml.first.name, '动漫');
    });
  });

  group('播放地址拆分', () {
    test('线路 / 集 / 集名三层', () {
      final sources = CmsVodClient.splitPlayUrl(
        'a\u0024\u0024\u0024b',
        '第1集\u0024https://x/1.m3u8#第2集\u0024https://x/2.m3u8\u0024\u0024\u0024https://y/all.mp4',
      );
      expect(sources.length, 2);
      expect(sources.first.episodes.length, 2);
      expect(sources.last.episodes.single.name, '第1集');
    });

    test('空地址返回空列表', () {
      expect(CmsVodClient.splitPlayUrl('lzm3u8', ''), isEmpty);
    });
  });

  group('地址校验', () {
    test('局域网与带账号的地址直接拒绝', () {
      expect(() => CmsVodClient('http://127.0.0.1/api.php'), throwsFormatException);
      expect(() => CmsVodClient('http://user:pw@a.test/api.php'), throwsFormatException);
      expect(() => CmsVodClient('ftp://a.test/api.php'), throwsFormatException);
    });
  });
}
