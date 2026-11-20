import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/online_source_store.dart';
import 'package:seewow/domain/online_source.dart';

/// 内置源包是**随包发的数据**，所以它自己要被当成交付物验证：
/// 文件在不在、能不能解析、跟代码里的种子是不是同一份。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内置源包文件存在且声明在 pubspec 里', () {
    final file = File(OnlineSourceStore.builtinPack);
    expect(file.existsSync(), isTrue, reason: '缺少 ${OnlineSourceStore.builtinPack}');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('assets/sources/builtin_sources.json'), isTrue);
  });

  test('内置源包解析出 14 个可用采集站', () {
    final raw = jsonDecode(File(OnlineSourceStore.builtinPack).readAsStringSync());
    expect(raw, isA<Map<String, Object?>>());
    final list = (raw as Map)['sites'];
    expect(list, isA<List<Object?>>());
    final sites = dedupeSites(
      (list as List).map(OnlineSite.fromJson).whereType<OnlineSite>(),
    );
    expect(sites.length, 14);
    for (final site in sites) {
      final uri = Uri.parse(site.api);
      expect(['http', 'https'], contains(uri.scheme));
      expect(uri.host, isNotEmpty);
    }
    // 同一接口换个写法只留一条：这是去重键在真数据上的回归。
    expect(sites.map((s) => s.hostKey).toSet().length, sites.length);
  });

  test('内置源包与代码里的种子是同一份清单', () {
    final raw = jsonDecode(File(OnlineSourceStore.builtinPack).readAsStringSync());
    final packed = (raw as Map)['sites'] as List;
    final fromFile = packed
        .map(OnlineSite.fromJson)
        .whereType<OnlineSite>()
        .map((s) => s.api)
        .toSet();
    final fromCode = seedOnlineSites.map((s) => s.api).toSet();
    expect(fromFile, fromCode);
  });

  testWidgets('asset bundle 里真的打进了内置源包', (tester) async {
    final text = await rootBundle.loadString(OnlineSourceStore.builtinPack);
    expect(text.contains('"packVersion"'), isTrue);
    expect(text.contains('caiji.dyttzyapi.com'), isTrue);
  });

  test('首次启动：没有本地清单时用内置源包铺满站点', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-sources-');
    addTearDown(() => dir.delete(recursive: true));
    final store = OnlineSourceStore(directory: dir);
    await store.load();
    expect(store.sites.length, 14);
    expect(store.enabledSites.length, 14);
    // 落盘一次，第二次启动不该重复叠加。
    final second = OnlineSourceStore(directory: dir);
    await second.load();
    expect(second.sites.length, 14);
  });
}
