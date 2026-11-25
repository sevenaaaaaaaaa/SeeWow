import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/playback_gestures.dart';

void main() {
  var locked = false, locks = 0, unmute = 0, taps = 0;
  double? seek, preview;
  bool? vSide;
  double? vFraction;
  var vBegins = 0, vEnds = 0;
  Future<void> mount(
    WidgetTester tester, {
    bool live = false,
    bool startLocked = false,
  }) async {
    locked = startLocked;
    locks = 0;
    unmute = 0;
    taps = 0;
    seek = null;
    preview = null;
    vSide = null;
    vFraction = null;
    vBegins = 0;
    vEnds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (_, setState) => PlaybackGestures(
              locked: locked,
              position: 100,
              duration: 600,
              seekEnabled: !live,
              onSeek: (v) => seek = v,
              onPreview: (v) => preview = v,
              onTap: () => taps++,
              onUnmute: () => unmute++,
              onVerticalBegin: (left) {
                vSide = left;
                vBegins++;
              },
              onVerticalUpdate: (left, fraction) {
                vSide = left;
                vFraction = fraction;
              },
              onVerticalEnd: () => vEnds++,
              onToggleLock: () => setState(() {
                locked = !locked;
                locks++;
              }),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('horizontal drag previews and commits once on release', (
    tester,
  ) async {
    await mount(tester);
    final finger = await tester.startGesture(const Offset(200, 300));
    await finger.moveTo(const Offset(500, 300));
    expect(preview, greaterThan(100));
    expect(seek, isNull);
    await finger.up();
    expect(seek, greaterThan(100));
    expect(preview, isNull);
    expect(unmute, 0);
    expect(taps, 0);
  });
  testWidgets('left/right holds accelerate and remain bounded', (tester) async {
    await mount(tester);
    final right = await tester.startGesture(const Offset(650, 300));
    await tester.pump(const Duration(seconds: 4));
    expect(preview, greaterThan(150));
    expect(seek, isNull);
    await right.up();
    expect(seek, lessThanOrEqualTo(600));
    final left = await tester.startGesture(const Offset(100, 300));
    await tester.pump(const Duration(seconds: 6));
    await left.up();
    expect(seek, 0);
    expect(unmute, 0);
  });
  testWidgets(
    'three fingers lock once; remaining finger cannot unmute or seek',
    (tester) async {
      await mount(tester);
      final a = await tester.startGesture(const Offset(200, 250), pointer: 1);
      final b = await tester.startGesture(const Offset(300, 250), pointer: 2);
      final c = await tester.startGesture(const Offset(400, 250), pointer: 3);
      await tester.pump(const Duration(milliseconds: 300));
      await c.up();
      await tester.pump(const Duration(milliseconds: 400));
      expect(locked, isTrue);
      expect(locks, 1);
      await b.up();
      await a.moveTo(const Offset(600, 250));
      await a.up();
      expect(seek, isNull);
      expect(unmute, 0);
      expect(taps, 0);
      final d = await tester.startGesture(const Offset(200, 250), pointer: 4);
      final e = await tester.startGesture(const Offset(300, 250), pointer: 5);
      await tester.pump(const Duration(milliseconds: 700));
      expect(locked, isFalse);
      expect(locks, 2);
      await d.up();
      await e.up();
      expect(seek, isNull);
      expect(unmute, 0);
    },
  );
  testWidgets('moving two fingers cancels lock; cancelled drag never commits', (
    tester,
  ) async {
    await mount(tester);
    final a = await tester.startGesture(const Offset(200, 250), pointer: 1);
    final b = await tester.startGesture(const Offset(300, 250), pointer: 2);
    await a.moveBy(const Offset(50, 0));
    await tester.pump(const Duration(seconds: 1));
    expect(locks, 0);
    await a.up();
    await b.up();
    final c = await tester.startGesture(const Offset(200, 250), pointer: 3);
    await c.moveBy(const Offset(200, 0));
    await c.cancel();
    expect(seek, isNull);
    expect(preview, isNull);
  });
  testWidgets('double tap unmutes once and is ignored during lock', (
    tester,
  ) async {
    await mount(tester);
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tapAt(const Offset(300, 300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(unmute, 1);
    expect(taps, 0);
    final a = await tester.startGesture(const Offset(200, 250), pointer: 1);
    final b = await tester.startGesture(const Offset(300, 250), pointer: 2);
    await tester.pump(const Duration(milliseconds: 700));
    await a.up();
    await b.up();
    await tester.tapAt(const Offset(300, 300));
    await tester.tapAt(const Offset(300, 300));
    expect(unmute, 1);
    expect(seek, isNull);
  });
  testWidgets('live playback rejects seeking; vertical swipe rejects seeking', (
    tester,
  ) async {
    await mount(tester, live: true);
    await tester.dragFrom(const Offset(100, 300), const Offset(400, 0));
    expect(seek, isNull);
    await mount(tester);
    await tester.dragFrom(const Offset(100, 200), const Offset(20, 200));
    expect(seek, isNull);
    expect(unmute, 0);
  });

  testWidgets('左半边上滑报亮度、右半边下滑报音量，都不跳进度', (tester) async {
    await mount(tester);
    final left = await tester.startGesture(const Offset(100, 400));
    await left.moveBy(const Offset(0, -120));
    expect(vBegins, 1);
    expect(vSide, isTrue, reason: 'x=100 在左半边');
    expect(vFraction, closeTo(.2, .01), reason: '120/600 屏高，上滑为正');
    await left.up();
    expect(vEnds, 1);
    expect(seek, isNull, reason: '竖向滑动不许变成跳进度');

    final right = await tester.startGesture(const Offset(700, 200));
    await right.moveBy(const Offset(0, 120));
    expect(vSide, isFalse, reason: 'x=700 在右半边');
    expect(vFraction, closeTo(-.2, .01), reason: '下滑为负');
    await right.up();
    expect(seek, isNull);
    expect(taps, 0);
  });

  testWidgets('横向拖动仍然是调进度，不被竖向逻辑抢走', (tester) async {
    await mount(tester);
    final finger = await tester.startGesture(const Offset(100, 300));
    await finger.moveBy(const Offset(300, 20));
    expect(vBegins, 0);
    expect(vFraction, isNull);
    await finger.up();
    expect(seek, greaterThan(100));
  });

  testWidgets('锁定时竖向滑动不给回调', (tester) async {
    await mount(tester, startLocked: true);
    final finger = await tester.startGesture(const Offset(100, 300));
    await finger.moveBy(const Offset(0, -150));
    await finger.up();
    expect(vBegins, 0);
    expect(vFraction, isNull);
    expect(seek, isNull);
  });

  test('verticalValue 夹在 0–1，上滑加、下滑减', () {
    expect(PlaybackGestures.verticalValue(.5, .25), closeTo(.75, 1e-9));
    expect(PlaybackGestures.verticalValue(.5, -.25), closeTo(.25, 1e-9));
    expect(PlaybackGestures.verticalValue(.9, .5), 1.0);
    expect(PlaybackGestures.verticalValue(.1, -.5), 0.0);
  });
}
