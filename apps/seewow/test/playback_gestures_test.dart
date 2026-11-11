import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/playback_gestures.dart';

void main() {
  var locked = false, locks = 0, unmute = 0, taps = 0;
  double? seek, preview;
  Future<void> mount(WidgetTester tester, {bool live = false}) async {
    locked = false;
    locks = 0;
    unmute = 0;
    taps = 0;
    seek = null;
    preview = null;
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
}
