import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/play_pause_orb.dart';

/// 播放／暂停键必须在画面上，而不是只在底部控件条里。
/// 两条断言钉的是同一个决定：播放中，画面中央就有一个能按的暂停键。
void main() {
  Future<void> mount(
    WidgetTester tester, {
    required bool playing,
    required VoidCallback onPressed,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: PlayPauseOrb(playing: playing, onPressed: onPressed),
        ),
      ),
    ),
  );

  AnimatedOpacity shell(WidgetTester tester) => tester.widget<AnimatedOpacity>(
    find.byKey(const ValueKey('playPauseOrb.opacity')),
  );

  testWidgets('播放中：画面中央是暂停键，按下去会回调', (tester) async {
    var taps = 0;
    await mount(tester, playing: true, onPressed: () => taps++);

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    expect(
      shell(tester).opacity,
      PlayPauseOrb.playingOpacity,
      reason: '播放时这个圆要淡，不能压在人脸和字幕上',
    );

    await tester.tap(find.byType(PlayPauseOrb));
    await tester.pump();
    expect(taps, 1, reason: '按在画面上就该直接暂停，不必先调出控件条');
  });

  testWidgets('暂停中：画面中央是播放键，满不透明', (tester) async {
    var taps = 0;
    await mount(tester, playing: false, onPressed: () => taps++);

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(shell(tester).opacity, 1);
    await tester.tap(find.byType(PlayPauseOrb));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('标签随状态切换，读屏与悬停都能说出它是哪一个', (tester) async {
    await mount(tester, playing: true, onPressed: () {});
    expect(find.byTooltip('暂停'), findsOneWidget);

    await mount(tester, playing: false, onPressed: () {});
    expect(find.byTooltip('播放'), findsOneWidget);
  });
}
