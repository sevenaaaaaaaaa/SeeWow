import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/spectrum_thumb.dart';

/// 给用户看的一张图：同一个进度条，三种状态（拿不到频段 / 一般能量 / 满格）。
/// 播放器本身是平台视图，截不到，所以这里只画那条进度条与游标。
class _Track extends StatelessWidget {
  const _Track({required this.ratio, required this.bands});
  final double ratio;
  final List<double> bands;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 28,
    child: Stack(
      alignment: Alignment.centerLeft,
      children: [
        Container(
          height: 3,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: Colors.white.withValues(alpha: .16),
          ),
        ),
        FractionallySizedBox(
          widthFactor: ratio,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: const LinearGradient(
                colors: [Color(0xFF7BD1C8), Color(0xFFF0C36D)],
              ),
            ),
          ),
        ),
        Positioned(
          left: (342 * ratio - SpectrumThumb.width / 2).clamp(
            0.0,
            342 - SpectrumThumb.width,
          ),
          child: SpectrumThumb(bands: bands),
        ),
      ],
    ),
  );
}

void main() {
  testWidgets('spectrum scrubber shot', (tester) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(390, 150);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const mid = [.18, .42, .66, .9, .55, .3, .22, .14, .08];
    const loud = [.55, .8, .95, .88, .7, .62, .45, .3, .18];

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFF0B0B0D),
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _Track(ratio: .22, bands: []),
                _Track(ratio: .52, bands: mid),
                _Track(ratio: .84, bands: loud),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 120));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final out = File('../../docs/screens/spectrum-2026-11-25-scrubber.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!);
    debugPrint('shot spectrum-scrubber (${bytes.length} bytes) -> ${out.path}');
    expect(bytes.length, greaterThan(1000));
  });
}
