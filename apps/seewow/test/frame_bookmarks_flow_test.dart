import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/features/frame_bookmarks_view.dart';
import 'package:seewow/playback/frame_bookmarks.dart';

/// 收藏过的画面必须能回去：列表要知道它来自哪部片，点一下要带着秒数走。
///
/// 用内存替身代替真机目录：这条测试要钉的是"列表 → 播放"这条线，
/// 不是 path_provider 在测试环境能不能用。
class _MemoryFrames extends FrameBookmarks {
  _MemoryFrames(this.frames);
  final List<FrameBookmark> frames;

  @override
  Future<List<FrameBookmark>> list({String? itemId}) async =>
      frames.where((f) => itemId == null || f.itemId == itemId).toList();

  @override
  Future<String> path(FrameBookmark frame) async => '/tmp/seewow-frame.jpg';
}

void main() {
  testWidgets('一条精彩帧能带回它所属的影片与秒数', (tester) async {
    final store = _MemoryFrames([
      FrameBookmark(
        id: 'a' * 64,
        itemId: 'dune2',
        title: 'Dune Part Two',
        seconds: 1793.25,
        createdAt: DateTime.utc(2026, 11, 25),
        note: '沙漠',
      ),
    ]);

    FrameBookmark? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showFrameBookmarks(
                  context,
                  store: store,
                  onOpen: (frame) => opened = frame,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.textContaining('Dune Part Two'), findsOneWidget);
    expect(find.text('播放这一帧'), findsOneWidget);

    await tester.tap(find.text('播放这一帧'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(opened, isNotNull);
    expect(opened!.itemId, 'dune2');
    expect(opened!.seconds, closeTo(1793.25, 0.001));
    expect(
      find.text('播放这一帧'),
      findsNothing,
      reason: '选完就该关掉列表，去看片子',
    );
  });
}
