import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/online_source_store.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/features/online_source_view.dart';

void main() {
  late Directory dir;
  late OnlineSourceStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-online-view-');
    store = OnlineSourceStore(directory: dir);
    await store.load();
    await WowSkin.I.load();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets('「在线源」空态给出站点数与边界说明', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnlineSourceView(
            store: store,
            iptv: IPTVStore(),
            onPlay: (_, {live = false}) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('在线源'), findsOneWidget);
    expect(find.textContaining('14  SITES'), findsOneWidget);
    expect(find.textContaining('只走纯 HTTP 接口'), findsOneWidget);
    expect(find.textContaining('问一遍已启用的 14 个采集站'), findsOneWidget);
  });

  testWidgets('空关键词不发请求，也不会崩', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OnlineSourceView(
            store: store,
            iptv: IPTVStore(),
            onPlay: (_, {live = false}) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(find.textContaining('没有找到'), findsNothing);
  });
}
