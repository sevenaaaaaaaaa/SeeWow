import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/playback_preferences.dart';
import 'package:seewow/playback/player_console.dart';

void main() {
  test('spectrum bands are silent at zero and fall off toward the top', () {
    expect(SpectrumShape.bands(0, bars: 8), everyElement(0));
    final loud = SpectrumShape.bands(1, bars: 8);
    expect(loud.length, 8);
    expect(loud.first, greaterThan(loud.last));
    expect(loud.every((v) => v >= 0 && v <= 1), isTrue);
    final quiet = SpectrumShape.bands(.4, bars: 8);
    for (var i = 0; i < 8; i++) {
      expect(quiet[i], lessThanOrEqualTo(loud[i]));
    }
  });

  test('a nonsense level cannot push a band out of range', () {
    final bands = SpectrumShape.bands(double.nan, bars: 6);
    expect(bands.every((v) => v == 0), isTrue);
    final over = SpectrumShape.bands(9, bars: 6);
    expect(over.every((v) => v <= 1), isTrue);
  });

  test('AB loop: A first, then B starts looping, a third tap starts over', () {
    final loop = AbLoop();
    expect(loop.enabled, isFalse);
    expect(loop.mark(12), '已标记 A 点');
    expect(loop.a, 12);
    expect(loop.b, isNull);
    expect(loop.mark(30), 'AB 循环已开启');
    expect(loop.a, 12);
    expect(loop.b, 30);
    expect(loop.enabled, isTrue);
    expect(loop.mark(4), '已标记 A 点');
    expect(loop.enabled, isFalse);
    expect(loop.a, 4);
  });

  test('a B point too close to A is refused instead of silently looping', () {
    final loop = AbLoop()..mark(10);
    expect(() => loop.mark(10.2), throwsFormatException);
    expect(loop.b, isNull);
  });

  testWidgets('the console states the AB range instead of hiding it', (tester) async {
    final loop = AbLoop()..mark(65);
    var marks = 0;
    var clears = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AbLoopControl(
            loop: loop,
            onMark: () => marks++,
            onClear: () => clears++,
          ),
        ),
      ),
    );
    expect(find.textContaining('A 01:05'), findsOneWidget);
    expect(find.textContaining('AB'), findsNothing);

    await tester.tap(find.textContaining('A 01:05'));
    expect(marks, 1);

    loop.mark(80);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AbLoopControl(
            loop: loop,
            onMark: () => marks++,
            onClear: () => clears++,
          ),
        ),
      ),
    );
    expect(find.textContaining('AB 01:05–01:20'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    expect(clears, 1);
  });
}
