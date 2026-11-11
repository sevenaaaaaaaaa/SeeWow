import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/theme.dart';
import 'package:seewow/features/watch_ai_view.dart';
import 'package:seewow/watch_ai/watch_ai_controller.dart';
import 'package:seewow/watch_ai/watch_ai_client.dart';
import 'package:seewow/watch_ai/watch_ai_settings.dart';
import 'package:seewow/watch_ai/watch_frame.dart';

class _PanelClient extends WatchAiClient {
  _PanelClient(super.settings);
  @override
  Future<String> complete({
    required WatchAiConfig config,
    required String system,
    required String prompt,
    Uint8List? frame,
  }) async => '测试解释';
}

void main() {
  testWidgets('opt in form fits a phone and requires a user configured API', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('watch-ai-ui-'),
    ))!;
    final settings = WatchAiSettings(
      directory: dir,
      writeSecret: (_, _) async {},
    );
    addTearDown(() async {
      settings.dispose();
      await dir.delete(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildWowTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => configureWatchAi(context, settings: settings),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(settings.config.enabled, false);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存配置'));
    await tester.pumpAndSettle();
    expect(find.text('开启前请填写 API 地址和模型名称'), findsOneWidget);
    expect(settings.config.enabled, false);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(settings.config.enabled, false);
  });

  for (final width in [375.0, 768.0]) {
    testWidgets(
      'companion panel remains usable at $width with and without keyboard',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final settings = WatchAiSettings();
        final ai = WatchAiController(
          title: 'Film',
          settings: settings,
          client: _PanelClient(settings),
        );
        addTearDown(() {
          ai.dispose();
          settings.dispose();
        });
        Future<void> mount(double inset) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildWowTheme(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 900),
                  viewInsets: EdgeInsets.only(bottom: inset),
                ),
                child: Scaffold(
                  body: WatchCompanionPanel(
                    controller: ai,
                    capture: () async => Uint8List(0),
                    onImportSubtitle: () async {},
                    onSelectSubtitle: () async {},
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await mount(0);
        expect(find.text('先接入你的 API'), findsOneWidget);
        expect(tester.takeException(), isNull);
        settings.config = const WatchAiConfig(
          enabled: true,
          endpoint: 'http://localhost/chat',
          model: 'film',
          allowFrames: true,
        );
        await mount(300);
        expect(find.text('本次问题附带当前画面'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(Checkbox));
        await tester.enterText(find.byType(TextField), '解释当前台词');
        await tester.tap(find.byTooltip('向小映提问'));
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, false);
      },
    );
  }
  testWidgets(
    'frame reduction bounds resolution and releases decoder resources',
    (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 1280, 720),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(1280, 720);
        final raw = await image.toByteData(format: ui.ImageByteFormat.png);
        final result = await reduceWatchFrame(raw!.buffer.asUint8List());
        final codec = await ui.instantiateImageCodec(result!);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 640);
        expect(frame.image.height, 360);
        expect(result.length, lessThanOrEqualTo(512 * 1024));
        frame.image.dispose();
        codec.dispose();
        image.dispose();
        picture.dispose();
        expect(await reduceWatchFrame(null), isNull);
        await expectLater(
          reduceWatchFrame(Uint8List(8 * 1024 * 1024 + 1)),
          throwsFormatException,
        );
      });
    },
  );
}
