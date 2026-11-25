import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/spectrum_thumb.dart';

void main() {
  test('heights 把任意段数重采样成固定根数，并夹在 0–1', () {
    expect(SpectrumThumb.heights(const [], 4), [0, 0, 0, 0]);
    expect(SpectrumThumb.heights(const [1.0], 3), [1.0, 1.0, 1.0]);
    expect(SpectrumThumb.heights(const [.2, .9, .4, .1], 2), [.9, .4]);
    expect(SpectrumThumb.heights(const [2.0, -1, double.nan], 3), [1.0, 0, 0]);
  });

  testWidgets('有频段时每根竖条都在，满能量就是满高', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SpectrumThumb(bands: [1, 1, 1, 1, 1, 1, 1, 1, 1]),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 9; i++) {
      expect(find.byKey(ValueKey('spectrumBar.$i')), findsOneWidget);
    }
    final bar = tester.getSize(find.byKey(const ValueKey('spectrumBar.0')));
    expect(bar.height, closeTo(28 - SpectrumThumb.padY * 2 - 2, .01));
  });

  testWidgets('没有频段时退回白点，不留一排空竖条', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: SpectrumThumb(bands: [])),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SpectrumThumb), findsOneWidget);
    expect(find.byKey(const ValueKey('spectrumBar.0')), findsNothing);
  });
}
