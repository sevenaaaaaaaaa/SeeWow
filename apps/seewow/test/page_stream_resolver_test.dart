import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/sources/page_stream_resolver.dart';

/// 样本是真实分享页的原始 HTML：极速（绝对地址写在 vid 里）与
/// 非凡（相对地址 + sign 查询串），另有一个「页面里没有直链」的对照。
String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('从页面文本里挑直链', () {
    test('极速：绝对地址写在脚本里', () {
      final base = Uri.parse('https://vv.jisuzyv.com/play/epYwLMXa');
      final found = PageStreamResolver.extract(
        fixture('share_page_jisu.html'),
        base: base,
      );
      expect(found, isNotNull);
      expect(
        found!.url,
        'https://vv.jisuzyv.com/play/epYwLMXa/index.m3u8',
      );
    });

    test('非凡：相对地址按页面来源补全，sign 保留', () {
      final base = Uri.parse(
        'https://vip.ffzy-play8.com/share/cd62214f8d15eb3a96937aaeb2ec75eb',
      );
      final found = PageStreamResolver.extract(
        fixture('share_page_ffzy.html'),
        base: base,
      );
      expect(found, isNotNull);
      expect(
        found!.url,
        'https://vip.ffzy-play8.com/20250718/839705_cd62214f/index.m3u8?sign=910994f991e10828d80f0519b97c1040',
      );
      expect(found.via, 'relative');
    });

    test('页面里没有直链 → 明确返回 null，不瞎猜', () {
      final found = PageStreamResolver.extract(
        fixture('share_page_no_stream.html'),
        base: Uri.parse('https://v.youku.com/v_show/id_XNjQ4.htm'),
      );
      expect(found, isNull);
    });

    test('JSON 里的转义斜杠也能认出来', () {
      const html =
          '{"play":"https:\\/\\/cdn.test\\/a\\/index.m3u8"}';
      final found = PageStreamResolver.extract(
        html,
        base: Uri.parse('https://page.test/x'),
      );
      expect(found?.url, 'https://cdn.test/a/index.m3u8');
    });

    test('非 http 或空地址直接判失败', () async {
      const resolver = PageStreamResolver();
      expect((await resolver.resolve('ftp://a.test/x')).ok, isFalse);
      expect((await resolver.resolve('')).ok, isFalse);
    });
  });
}
