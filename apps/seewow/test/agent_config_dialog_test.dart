import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/agent/agent_controller.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/skin.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/features/agent_view.dart';

void main() {
  late Directory dir;
  late LibraryStore library;
  late AgentController agent;

  setUp(() async {
    WowSkin.I.reset();
    dir = await Directory.systemTemp.createTemp('seewow-agent-dialog-');
    library = LibraryStore(directory: dir);
    agent = AgentController(
      library,
      directory: dir,
      readSecret: (_) async => '',
      writeSecret: (_, _) async {},
    );
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWowTheme(),
        home: Scaffold(body: AgentView(agent: agent, iptv: IPTVStore(), onOpen: (_) {})),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('接入 AI 模型'));
    await tester.pumpAndSettle();
  }

  testWidgets('platform preset fills the endpoint and model', (tester) async {
    await mount(tester);
    expect(find.text('接入你的 AI 模型'), findsOneWidget);
    await tester.tap(find.text('自定义 / 其他兼容服务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek 深度求索').last);
    await tester.pumpAndSettle();
    expect(
      find.text('https://api.deepseek.com/v1/chat/completions'),
      findsOneWidget,
    );
    expect(find.text('deepseek-chat'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving a bare domain stores the full endpoint', (tester) async {
    await mount(tester);
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'api.openai.com/v1');
    await tester.pump();
    await tester.enterText(fields.at(1), 'gpt-4o-mini');
    await tester.pump();
    await tester.tap(find.text('保存配置'));
    // The write itself is fire-and-forget for this check; configure() assigns
    // the normalized endpoint before awaiting disk.
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      agent.endpoint,
      'https://api.openai.com/v1/chat/completions',
    );
    expect(agent.model, 'gpt-4o-mini');
    expect(find.textContaining('请填写'), findsNothing);
  });
}
