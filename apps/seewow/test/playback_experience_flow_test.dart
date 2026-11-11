import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/features/frame_bookmarks_view.dart';
import 'package:seewow/features/playback_settings_view.dart';
import 'package:seewow/features/voice_translation_view.dart';
import 'package:seewow/playback/cinema_entrance.dart';
import 'package:seewow/playback/frame_bookmarks.dart';
import 'package:seewow/playback/playback_preferences.dart';

void main() {
  late Directory dir;
  setUpAll(() async {
    if (Platform.environment['SEEWOW_SHOTS'] == '1') {
      final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
      if (await font.exists())
        await (FontLoader('CinemaTest')..addFont(
              Future.value(ByteData.sublistView(await font.readAsBytes())),
            ))
            .load();
    }
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-playback-ui-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('seewow/native'),
          (call) async => call.method == 'secret.write' ? true : null,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('seewow/native'), null);
    await dir.delete(recursive: true);
  });
  Future<void> mount(
    WidgetTester tester,
    double width,
    Widget child, {
    bool reduced = false,
    double height = 850,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('playback-shot'),
        child: MaterialApp(
          theme: ThemeData(
            brightness: width == 768 ? Brightness.light : Brightness.dark,
            fontFamily: Platform.environment['SEEWOW_SHOTS'] == '1'
                ? 'CinemaTest'
                : null,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: reduced,
              textScaler: TextScaler.linear(width == 375 ? 1.6 : 1),
            ),
            child: child!,
          ),
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.runAsync(() async {
      await tester.tap(find.text(label).last);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    // Modal initState starts file IO during a fake-time frame; alternate frames
    // with real IO turns before waiting for its loading indicator to settle.
    for (var turn = 0; turn < 12; turn++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pumpAndSettle();
  }

  Future<void> screenshot(WidgetTester tester, String name) async {
    if (Platform.environment['SEEWOW_SHOTS'] != '1') return;
    await tester.runAsync(() async {
      final image = await tester
          .renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('playback-shot')),
          )
          .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('/tmp/seewow-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final style in [EntranceStyle.disc, EntranceStyle.spotlight]) {
    testWidgets(
      '$style entrance is bounded, skippable and only completes once',
      (tester) async {
        var done = 0;
        await mount(
          tester,
          768,
          CinemaEntrance(
            style: style,
            title: '为这一刻留一束光 · 私人影院',
            onComplete: () => done++,
          ),
        );
        await tester.pump(const Duration(milliseconds: 700));
        expect(done, 0);
        await screenshot(tester, 'entrance-${style.name}');
        await tester.tap(find.text('跳过片头'));
        await tester.pump(const Duration(seconds: 4));
        expect(done, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('reduced motion skips the entrance without a running animation', (
    tester,
  ) async {
    var done = 0;
    await mount(
      tester,
      375,
      CinemaEntrance(
        style: EntranceStyle.disc,
        title: 'Movie',
        onComplete: () => done++,
      ),
      reduced: true,
    );
    await tester.pump();
    expect(done, 1);
    await tester.pump(const Duration(seconds: 4));
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });
  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets('playback and voice API forms remain reachable at $width', (
      tester,
    ) async {
      await mount(
        tester,
        width,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => configurePlayback(context),
            child: const Text('Open'),
          ),
        ),
      );
      await tap(tester, 'Open');
      await tap(tester, '保存播放偏好');
      expect(find.text('放映与播放'), findsNothing);
      await mount(
        tester,
        width,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => configureVoiceTranslation(context),
            child: const Text('Open'),
          ),
        ),
      );
      await tap(tester, 'Open');
      await tap(tester, '保存语音服务');
      expect(find.textContaining('服务地址需为'), findsOneWidget);
      if (width == 768) await screenshot(tester, 'voice-api-settings');
      expect(tester.takeException(), isNull);
      await tap(tester, '取消');
    });
  }
  testWidgets(
    'frame gallery opens locally, seeks only on request and removes with confirmation',
    (tester) async {
      final store = FrameBookmarks(directory: dir);
      final image = await tester.runAsync(
        () => File('assets/branding/tmdb.png').readAsBytes(),
      );
      final media = MediaItem(
        id: 'a',
        sourceId: 'local',
        kind: MediaKind.movie,
        title: '测试画面',
        locator: '/private/movie',
      );
      await tester.runAsync(() => store.add(media, 12, image!, note: '收藏备注'));
      double? selected;
      await mount(
        tester,
        375,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showFrameBookmarks(
              context,
              store: store,
              itemId: 'a',
              onSelect: (f) => selected = f.seconds,
            ),
            child: const Text('Open'),
          ),
        ),
      );
      await tap(tester, 'Open');
      expect(find.text('收藏备注'), findsOneWidget);
      expect(selected, isNull);
      await tap(tester, '回到此刻');
      expect(selected, 12);
      await tap(tester, 'Open');
      await tap(tester, '移除收藏');
      await tap(tester, '取消');
      expect(await tester.runAsync(() => store.list()), hasLength(1));
      await tap(tester, '移除收藏');
      await tap(tester, '移除收藏');
      expect(await tester.runAsync(() => store.list()), isEmpty);
      expect(find.textContaining('还没有收藏画面'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('entrance remains usable in phone landscape with a long title', (
    tester,
  ) async {
    var done = 0;
    await mount(
      tester,
      900,
      CinemaEntrance(
        style: EntranceStyle.spotlight,
        title: 'A long film title / العربية / བོད་ཡིག / 日本語 / 한국어',
        onComplete: () => done++,
      ),
      height: 450,
    );
    await tester.pump(const Duration(seconds: 3));
    expect(done, 1);
    expect(tester.takeException(), isNull);
  });
}
