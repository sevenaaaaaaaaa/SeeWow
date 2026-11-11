import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/iptv_store.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/data/local_scanner.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/subscription.dart';
import 'package:seewow/features/sources_view.dart';
import 'package:seewow/features/subscription_dialog.dart';

import 'subscription_test.dart' show MemorySubscriptionReader;

class PreviewStore extends IPTVStore {
  PreviewStore(MemorySubscriptionReader reader) : super(reader: reader);
  SubscriptionPreview? imported;
  @override
  Future<bool> importPreview(
    SubscriptionPreview data, {
    required String name,
    String? source,
    String? epgUrl,
    bool allowLocalNetwork = false,
  }) async {
    imported = data;
    return true;
  }
}

void main() {
  setUpAll(() async {
    if (Platform.environment['SEEWOW_SHOTS'] != '1') return;
    final font = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (font.existsSync()) {
      final bytes = await font.readAsBytes();
      await (FontLoader(
        'CinemaTest',
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final width in [375.0, 768.0, 1440.0]) {
    testWidgets(
      'preview and explicit child selection fit $width without importing',
      (tester) async {
        tester.view.physicalSize = Size(width, width == 375 ? 667 : 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final reader = MemorySubscriptionReader()
          ..documents.addAll({
            'https://example.test/root': '{"urls":[{"name":"Home","url":"https://example.test/child"}],"spider":"https://evil.test/plugin.jar"}',
            'https://example.test/child':
                'Home,#genre#\nA,https://example.test/stream',
          });
        final store = PreviewStore(reader);
        addTearDown(store.dispose);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('app-shot'),
            child: MaterialApp(
              theme: Platform.environment['SEEWOW_SHOTS'] == '1'
                  ? ThemeData.dark().copyWith(
                      textTheme: ThemeData.dark().textTheme.apply(
                        fontFamily: 'CinemaTest',
                      ),
                    )
                  : ThemeData.dark(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 375 ? 1.6 : 1),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: RepaintBoundary(
                  key: const ValueKey('shot'),
                  child: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => importSubscription(
                        context,
                        store,
                        initial: 'https://example.test/root',
                      ),
                      child: const Text('打开导入'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开导入'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('读取预览'));
        await tester.pumpAndSettle();
        expect(store.imported, isNull);
        expect(reader.requests, ['https://example.test/root']);
        expect(find.textContaining('不会下载或执行'), findsOneWidget);
        await tester.ensureVisible(find.text('Home'));
        await tester.tap(find.text('Home'));
        await tester.pumpAndSettle();
        expect(reader.requests, [
          'https://example.test/root',
          'https://example.test/child',
        ]);
        expect(store.imported, isNull);
        expect(tester.takeException(), isNull);
        if (Platform.environment['SEEWOW_SHOTS'] == '1') {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('app-shot')),
            );
            final shot = await boundary.toImage();
            final bytes = await shot.toByteData(format: ui.ImageByteFormat.png);
            await Directory('/tmp/seewow-subscription-shots')
                .create(recursive: true);
            await File('/tmp/seewow-subscription-shots/$width.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            shot.dispose();
          });
        }
        await tester.tap(find.text('确认导入频道'));
        await tester.pumpAndSettle();
        expect(store.imported!.channels.single.name, 'A');
      },
    );
  }
  testWidgets(
    'cyclic depots never fetch a child and cancel leaves no subscription',
    (tester) async {
      final reader = MemorySubscriptionReader()
        ..documents['https://example.test/root'] =
            '{"urls":[{"name":"Cycle","url":"https://example.test/root"}]}';
      final store = PreviewStore(reader);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => importSubscription(
                  context,
                  store,
                  initial: 'https://example.test/root',
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('读取预览'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cycle'));
      await tester.tap(find.text('Cycle'));
      await tester.pumpAndSettle();
      expect(reader.requests, ['https://example.test/root']);
      expect(find.textContaining('循环引用'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '确认导入频道'),
      );
      expect(button.onPressed, isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(store.imported, isNull);
      expect(store.playlists, isEmpty);
    },
  );
  testWidgets(
    'Telegram local directory scans actual files and preserves AI restriction on disk',
    (tester) async {
      late Directory dir, mediaDir;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('seewow-telegram-local-');
        mediaDir = await Directory('${dir.path}/media').create();
        await File('${mediaDir.path}/Lesson.01.mp4').writeAsBytes([0]);
        await File('${mediaDir.path}/notes.txt').writeAsString('not media');
      });
      addTearDown(() => dir.delete(recursive: true));
      final library = (await tester.runAsync(
        () async => LibraryStore(directory: dir)..scanner = LocalScanner().scan,
      ))!;
      addTearDown(library.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => connectLocalMediaFolder(
          context,
          library,
          pickDirectory: () async => mediaDir.path,
        ),
      );
      final originalId = library.sources.single.id;
      expect(library.items.single.aiAllowed, isTrue);
      await tester.runAsync(
        () => connectLocalMediaFolder(
          context,
          library,
          providerId: 'telegramLocal',
          pickDirectory: () async => mediaDir.path,
        ),
      );
      expect(library.sources.single.kind, SourceKind.local);
      expect(library.sources.single.providerId, 'telegramLocal');
      expect(library.sources.single.id, originalId);
      expect(library.sources, hasLength(1));
      expect(library.items.single.aiAllowed, isFalse);
      expect(library.items.single.copyWith(position: 5).aiAllowed, isFalse);
      await tester.runAsync(
        () => connectLocalMediaFolder(
          context,
          library,
          pickDirectory: () async => mediaDir.path,
        ),
      );
      expect(library.items.single.aiAllowed, isFalse);
      final restored = LibraryStore(directory: dir);
      await tester.runAsync(restored.load);
      expect(restored.items.single.aiAllowed, isFalse);
      restored.dispose();
    },
  );
}
