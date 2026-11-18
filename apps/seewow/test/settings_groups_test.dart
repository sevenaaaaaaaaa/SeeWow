import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/agent/agent_controller.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/downloads/download_manager.dart';
import 'package:seewow/features/settings_view.dart';

void main() {
  late Directory dir;
  late LibraryStore store;
  late AgentController agent;
  late DownloadManager downloads;

  setUp(() async {
    WowSkin.I.reset();
    dir = await Directory.systemTemp.createTemp('seewow-settings-');
    store = LibraryStore(directory: dir);
    agent = AgentController(
      store,
      directory: dir,
      readSecret: (_) async => '',
      writeSecret: (_, _) async {},
    );
    downloads = DownloadManager(directory: dir);
  });

  tearDown(() async {
    downloads.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> mount(
    WidgetTester tester,
    Widget view, {
    double width = 1440,
    double height = 4000,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWowTheme(),
        home: Scaffold(body: view),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings reads as titled groups, not one flat list', (
    tester,
  ) async {
    await mount(
      tester,
      SettingsView(store: store, agent: agent, downloads: downloads),
    );
    for (final group in ['外观与氛围', 'AI 与智能', '播放', '字幕', '存储', '内容与来源']) {
      expect(find.text(group), findsOneWidget, reason: group);
    }
    expect(find.text('未接入 · 使用本地规则模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a configured model is named in the AI row', (tester) async {
    agent.endpoint = 'https://api.deepseek.com/v1/chat/completions';
    agent.model = 'deepseek-chat';
    await mount(
      tester,
      SettingsView(store: store, agent: agent, downloads: downloads),
    );
    expect(find.text('当前：deepseek-chat · api.deepseek.com'), findsOneWidget);
  });

  testWidgets('grouped settings still fit a phone width', (tester) async {
    await mount(
      tester,
      SettingsView(store: store, agent: agent, downloads: downloads),
      width: 375,
      height: 6000,
    );
    expect(find.text('AI 与智能'), findsOneWidget);
    expect(find.text('播放'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
