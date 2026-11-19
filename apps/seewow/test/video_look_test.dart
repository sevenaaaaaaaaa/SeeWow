import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/video_look.dart';

void main() {
  test('the console offers eight looks with distinct ids', () {
    expect(VideoLook.presets.length, 8);
    final ids = VideoLook.presets.map((look) => look.id).toSet();
    expect(ids.length, VideoLook.presets.length);
    for (final look in VideoLook.presets) {
      expect(look.matrix.length, 20, reason: look.id);
      expect(look.label.trim().isNotEmpty, isTrue, reason: look.id);
      expect(look.blurb.trim().isNotEmpty, isTrue, reason: look.id);
    }
  });

  test('native is the identity grade, so the picture is untouched', () {
    expect(VideoLook.native.matrix, VideoLook.grade());
    expect(VideoLook.native.touchesPixels, isFalse);
  });

  test('unknown or missing ids fall back to native', () {
    expect(VideoLook.byId(null).id, 'native');
    expect(VideoLook.byId('').id, 'native');
    expect(VideoLook.byId('no-such-look').id, 'native');
    expect(VideoLook.byId('film').id, 'film');
  });

  test('ink removes colour: the three output channels share one weight set', () {
    final m = VideoLook.byId('ink').matrix;
    for (var c = 0; c < 3; c++) {
      expect(m[c], closeTo(m[5 + c], 1e-9));
      expect(m[c], closeTo(m[10 + c], 1e-9));
    }
    // Luminance weights, not an equal mix: green carries the most detail.
    expect(m[1], greaterThan(m[0]));
    expect(m[0], greaterThan(m[2]));
  });

  test('every overlay strength stays inside its documented range', () {
    for (final look in VideoLook.presets) {
      expect(look.scanlines, inInclusiveRange(0, 1), reason: look.id);
      expect(look.grain, inInclusiveRange(0, 1), reason: look.id);
      expect(look.vignette, inInclusiveRange(0, 1), reason: look.id);
      expect(look.flicker, inInclusiveRange(0, 1), reason: look.id);
      expect(look.bloom, inInclusiveRange(0, 1), reason: look.id);
      expect(look.weave, inInclusiveRange(0, 4), reason: look.id);
    }
  });

  testWidgets('a look wraps the picture; native leaves it alone', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: VideoLookView(look: VideoLook.native, child: SizedBox.expand())),
    );
    expect(find.byType(ColorFiltered), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: VideoLookView(look: VideoLook.byId('crt'), child: const SizedBox.expand()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 40));
    expect(find.byType(ColorFiltered), findsOneWidget);
  });
}
