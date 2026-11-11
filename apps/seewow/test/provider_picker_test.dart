import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/features/sources_view.dart';

void main() {
  late Directory dir;
  late LibraryStore library;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-picker-');
    library = LibraryStore(directory: dir);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    double width, {
    double height = 900,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  chooseSourceProvider(context, library, IPTVStore()),
              child: const Text('选择服务'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('选择服务'));
    await tester.pumpAndSettle();
  }

  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets(
      'provider picker fits $width and routes a cloud service to an explicit gateway form',
      (tester) async {
        addTearDown(tester.view.reset);
        await mount(tester, width, height: width == 375 ? 667 : 900);
        await tester.enterText(find.byType(TextField), '115');
        await tester.pumpAndSettle();
        expect(find.text('115 网盘'), findsOneWidget);
        await tester.tap(find.text('115 网盘'));
        await tester.pumpAndSettle();
        expect(find.text('网关挂载根目录'), findsOneWidget);
        expect(find.text('OpenList / Alist API（网关）'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(library.sources, isEmpty);
      },
    );
  }
  testWidgets(
    'Navidrome offers music credentials rather than a movie API key',
    (tester) async {
      addTearDown(tester.view.reset);
      await mount(tester, 768);
      await tester.enterText(find.byType(TextField), 'navidrome');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Navidrome'));
      await tester.pumpAndSettle();
      expect(find.text('用户名'), findsOneWidget);
      expect(find.text('密码（单独保存，不发给 AI）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('editing a source retains identity and current gateway scope', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(768, 900);
    tester.view.devicePixelRatio = 1;
    final source = MediaSource(
      id: 'stable',
      kind: SourceKind.openlist,
      providerId: 'quark',
      name: 'My Drive',
      location: 'https://gateway.test',
      rootPath: '/夸克/影片',
    );
    library.sources.add(source);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => connectSource(
                context,
                library,
                IPTVStore(),
                existing: source,
              ),
              child: const Text('编辑'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑连接'), findsOneWidget);
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    expect(fields.any((f) => f.controller?.text == '/夸克/影片'), isTrue);
    expect(fields.any((f) => f.controller?.text == 'My Drive'), isTrue);
    expect(library.sources.single.id, 'stable');
    expect(tester.takeException(), isNull);
  });
}
