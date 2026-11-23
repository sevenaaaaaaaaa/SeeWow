import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/online_source_store.dart';
import 'package:seewow/domain/online_source.dart';

/// 内置源包是**随包发的数据**，所以它自己要被当成交付物验证：
/// 文件在不在、能不能解析、跟代码里的种子是不是同一份、换版时旧机器会不会被更新。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内置源包文件存在且声明在 pubspec 里', () {
    final file = File(OnlineSourceStore.builtinPack);
    expect(file.existsSync(), isTrue, reason: '缺少 ${OnlineSourceStore.builtinPack}');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    // 声明的是目录：公开包把文件挪走后不必改 pubspec。
    expect(pubspec.contains('assets/sources/'), isTrue);
  });

  test('内置源包解析出可用采集站，且去重键唯一', () {
    final raw = jsonDecode(File(OnlineSourceStore.builtinPack).readAsStringSync());
    expect(raw, isA<Map<String, Object?>>());
    final list = (raw as Map)['sites'];
    expect(list, isA<List<Object?>>());
    final sites = dedupeSites(
      (list as List).map(OnlineSite.fromJson).whereType<OnlineSite>(),
    );
    // 数量跟着代码种子走：加站只需要改一处，测试不会变成绊脚石。
    expect(sites.length, seedOnlineSites.length);
    expect(sites.length, greaterThanOrEqualTo(12), reason: '内置站点太少，搜不到东西');
    for (final site in sites) {
      final uri = Uri.parse(site.api);
      expect(['http', 'https'], contains(uri.scheme));
      expect(uri.host, isNotEmpty);
    }
    // 同一接口换个写法只留一条：这是去重键在真数据上的回归。
    expect(sites.map((s) => s.hostKey).toSet().length, sites.length);
  });

  test('v1 那批已经连不上的站点不该再出现在内置清单里', () {
    final raw = jsonDecode(File(OnlineSourceStore.builtinPack).readAsStringSync());
    final apis = ((raw as Map)['sites'] as List)
        .map(OnlineSite.fromJson)
        .whereType<OnlineSite>()
        .map((s) => s.api)
        .toList();
    for (final dead in [
      'caiji.dyttzyapi.com',
      'cj.lziapi.com',
      'suoniapi.com',
      'api.ukuapi.com',
      'jszyapi.com',
      'zy.jinchancaiji.com',
      'vs.okcdn100.top',
      'bfzyapi.com',
      'wolongzyw.com',
      'tyyszy.com',
    ]) {
      expect(
        apis.any((api) => api.contains(dead)),
        isFalse,
        reason: '$dead 在 2026-11-23 实测已失效，不该随包再发',
      );
    }
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
    expect(text.contains('"packVersion": "2"'), isTrue);
    expect(text.contains('api.zuidapi.com'), isTrue);
  });

  test('首次启动：没有本地清单时用内置源包铺满站点', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-sources-');
    addTearDown(() => dir.delete(recursive: true));
    final store = OnlineSourceStore(directory: dir);
    await store.load();
    expect(store.sites.length, seedOnlineSites.length);
    expect(store.enabledSites.length, seedOnlineSites.length);
    // 落盘一次，第二次启动不该重复叠加。
    final second = OnlineSourceStore(directory: dir);
    await second.load();
    expect(second.sites.length, seedOnlineSites.length);
  });

  test('装过 v1 的机器：旧内置站被换成新包，用户自己的站一条不动', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-migrate-');
    addTearDown(() => dir.delete(recursive: true));
    // v1 时代的清单：14 个内置站 + 用户自己加的一条，没有 packVersion 字段。
    final legacy = {
      'sites': [
        {
          'id': 'dytt',
          'name': '电影天堂',
          'api': 'http://caiji.dyttzyapi.com/api.php/provide/vod',
          'enabled': true,
        },
        {
          'id': 'lzi',
          'name': '量子',
          'api': 'https://cj.lziapi.com/api.php/provide/vod/',
          'enabled': true,
        },
        {
          'id': 'custom-1',
          'name': '我自己的站',
          'api': 'https://my.example.com/api.php/provide/vod/',
          'enabled': true,
        },
      ],
    };
    File('${dir.path}/online_sources.json')
        .writeAsStringSync(jsonEncode(legacy));

    final store = OnlineSourceStore(directory: dir);
    await store.load();

    final ids = store.sites.map((s) => s.id).toList();
    expect(ids, isNot(contains('dytt')), reason: 'v1 的死站要清掉');
    expect(ids, isNot(contains('lzi')), reason: 'v1 的死站要清掉');
    expect(ids, contains('custom-1'), reason: '用户自己的站不能被迁移吃掉');
    expect(ids, contains('zuidapi'), reason: '新包要铺进来');
    expect(store.sites.length, seedOnlineSites.length + 1);

    // 迁移结果要落盘，否则下次启动又回到旧清单。
    final saved =
        jsonDecode(File('${dir.path}/online_sources.json').readAsStringSync())
            as Map;
    expect(saved['packVersion'], '2');
    expect(
      (saved['sites'] as List).map((s) => (s as Map)['id']),
      isNot(contains('dytt')),
    );
  });

  test('公开包（noBuiltinSources）既不铺源包也不铺代码种子', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-public-');
    addTearDown(() => dir.delete(recursive: true));
    final store = OnlineSourceStore(directory: dir, noBuiltinSources: true);
    await store.load();
    expect(store.sites, isEmpty, reason: '上 GitHub 那份不随包带站点');
    expect(store.enabledSites, isEmpty);

    // 用户自己加的照常可用，也会落盘。
    expect(await store.addSite('我的站', 'https://a.test/api.php/provide/vod'), isTrue);
    expect(store.sites.length, 1);
    final again = OnlineSourceStore(directory: dir, noBuiltinSources: true);
    await again.load();
    expect(again.sites.length, 1, reason: '用户自己加的站要活下来');
  });

  test('已经是本版清单的机器：重复 load 不叠加、不重置用户的开关', () async {
    final dir = await Directory.systemTemp.createTemp('seewow-stable-');
    addTearDown(() => dir.delete(recursive: true));
    final store = OnlineSourceStore(directory: dir);
    await store.load();
    final first = store.sites.length;
    // 用户关掉第一个站，模拟他自己的选择。
    await store.toggle(store.sites.first, false);

    final again = OnlineSourceStore(directory: dir);
    await again.load();
    expect(again.sites.length, first);
    expect(again.enabledSites.length, first - 1, reason: '用户的开关不该被迁移重置');
  });
}
