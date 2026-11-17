import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/features/sources_view.dart';
import 'package:seewow/sources/plex_scanner.dart';

class _FakePlex extends PlexScanner {
  @override
  Future<List<PlexSection>> sections(MediaSource source, String token) async {
    if (token != 'tok-123') throw StateError('unexpected token: $token');
    return const [
      PlexSection(key: '1', title: '电影', type: 'movie', count: 10),
      PlexSection(key: '2', title: '剧集', type: 'show', count: 20),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-repick-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async => dir.path);
    final support = Directory('${dir.path}/SeeWow')..createSync(recursive: true);
    File('${support.path}/secrets.json').writeAsStringSync(
      jsonEncode({'source.p1': 'tok-123'}),
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, null);
    await dir.delete(recursive: true);
  });

  testWidgets('RM-04 编辑 Plex 来源可直接改选资料库，不重登录', (tester) async {
    final store = LibraryStore(directory: dir);
    final source = MediaSource(
      id: 'p1',
      kind: SourceKind.plex,
      name: 'Plex 客厅',
      location: 'http://127.0.0.1:9',
      providerId: 'plex',
      folders: const ['1'],
      lastScan: DateTime(2026, 11, 17),
    );
    store.sources.add(source);

    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => connectSource(
                context,
                store,
                IPTVStore(),
                existing: source,
                plexScanner: _FakePlex(),
              ),
              child: const Text('编辑'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('重新选择资料库'), findsOneWidget);

    await tester.ensureVisible(find.text('重新选择资料库'));
    await tester.tap(find.text('重新选择资料库'));
    // 读已存 token 是真实文件 IO：在真实时区里等它，再 pump 让选择框上线。
    // 单靠一次固定延时在 CI 上会不够（那边更慢），所以按状态轮询。
    for (var i = 0; i < 50; i++) {
      if (find.text('选择要导入的资料库').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('选择要导入的资料库'), findsOneWidget);

    await tester.tap(find.text('剧集'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只导入勾选的'));
    await tester.pumpAndSettle();
    expect(find.text('选择要导入的资料库'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('测试连接并导入'));
      // Wait for the real write to land instead of settling the spinner.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (store.sources.single.folders.length == 2) break;
      }
    });
    await tester.pump();
    expect(store.sources.single.folders.toSet(), {'1', '2'});
  });
}