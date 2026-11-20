import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/sources/parse_component.dart';
import 'package:seewow/sources/web_page_parse.dart';

void main() {
  group('分享页判定', () {
    test('正版站外链与 /share/ 页算分享页', () {
      expect(isSharePageUrl('https://v.youku.com/v_show/id_XNj.html'), isTrue);
      expect(isSharePageUrl('https://vip.ffzy-play9.com/share/cd62'), isTrue);
      expect(isSharePageUrl('https://vv.jisuzyv.com/play/epYwLMXa'), isTrue);
    });

    test('媒体直链不算分享页', () {
      expect(isSharePageUrl('https://x.test/a/index.m3u8'), isFalse);
      expect(isSharePageUrl('https://x.test/v.mp4?t=1'), isFalse);
      expect(isSharePageUrl('/local/path.mkv'), isFalse);
    });
  });

  group('地址提取', () {
    test('页面里藏着的转义地址能取出来', () {
      const html =
          'var cfg={"url":"https:\\/\\/m.test\\/202610\\/index.m3u8?sign=abc"};';
      expect(mediaUrlFrom(html), 'https://m.test/202610/index.m3u8?sign=abc');
    });

    test('?url= 里裹着的地址解一层', () {
      const wrapped =
          'https://jx.test/jx.php?url=https%3A%2F%2Fm.test%2F1.m3u8';
      expect(unwrapUrlParam(wrapped), 'https://m.test/1.m3u8');
      final inner = unwrapUrlParam(wrapped)!;
      expect(mediaUrlFrom(inner), 'https://m.test/1.m3u8');
    });

    test('没有地址时返回 null，不瞎猜', () {
      expect(mediaUrlFrom('<html>无</html>'), isNull);
      expect(mediaUrlFrom(''), isNull);
      expect(unwrapUrlParam('https://a.test/play'), isNull);
    });
  });

  group('解析组件登记', () {
    test('直链组件任何平台都可用，且不执行远端脚本', () {
      final direct = parseComponent('direct')!;
      expect(direct.executesRemoteScripts, isFalse);
      expect(direct.runsHere, isTrue);
    });

    test('网页解析只登记在手机端，并明确标注执行远端脚本', () {
      final webview = parseComponent('webview')!;
      expect(webview.executesRemoteScripts, isTrue);
      expect(webview.platforms, {'ios', 'android'});
      expect(webview.runsHere, Platform.isIOS || Platform.isAndroid);
    });

    test('当前平台可用清单按代价给出', () {
      final available = availableParsers().map((c) => c.id).toList();
      expect(available.first, 'direct');
      expect(parseComponent('不存在'), isNull);
    });
  });
}
