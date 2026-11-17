import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/data/library_store.dart';
import 'package:seewow/design/skeleton.dart';
import 'package:seewow/domain/media_item.dart';

MediaSource local(String id) => MediaSource(
  id: id,
  kind: SourceKind.local,
  name: '本地',
  location: '/media',
);

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seewow-slow-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test('扫描超过阈值会标记 slowScans，扫完清除', () async {
    final store = LibraryStore(
      directory: dir,
      slowScanAfter: const Duration(milliseconds: 60),
    );
    final source = local('s1');
    store.sources.add(source);
    final gate = Completer<List<MediaItem>>();
    store.scanner = (_) => gate.future;
    final scan = store.rescan(source);
    expect(store.slowScans, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(store.slowScans, contains('s1'));
    gate.complete(const []);
    await scan;
    expect(store.slowScans, isEmpty);
    expect(store.scanning, isFalse);
    store.dispose();
  });

  testWidgets('首扫时给骨架卡而不是空白', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [LibrarySkeleton(columns: 3, animate: false)],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.bySemanticsLabel('正在载入片库'), findsNWidgets(6));
    handle.dispose();
  });
}