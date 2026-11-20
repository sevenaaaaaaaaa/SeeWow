// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/brand_mark.dart';

/// Renders the brand mark to PNG files.
///
/// One source of truth: the app icon sets, the in-app mark and this preview
/// sheet all come from WowMarkPainter. Run with:
///   flutter test tool/render_brand_test.dart
/// Output defaults to build/brand; override with the BRAND_OUT env var.
void main() {
  final out = Platform.environment['BRAND_OUT'] ?? 'build/brand';

  Future<void> shot(
    WidgetTester tester,
    String name,
    double size,
    Widget child, {
    Size? canvas,
  }) async {
    final extent = canvas ?? Size(size, size);
    await tester.binding.setSurfaceSize(extent);
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(key: key, child: child),
      ),
    );
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(out + '/' + name);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    print('wrote ' + file.path + ' (' + bytes.lengthInBytes.toString() + ' bytes)');
  }

  testWidgets('render brand assets', (tester) async {
    await tester.runAsync(() async {
      await shot(
        tester,
        'icon-1024-square.png',
        1024,
        const WowMark(size: 1024, tile: true, tileRadius: 0),
      );
      await shot(
        tester,
        'icon-1024-squircle.png',
        1024,
        const WowMark(size: 1024, tile: true),
      );
      await shot(
        tester,
        'icon-128-squircle.png',
        128,
        const WowMark(size: 128, tile: true),
      );
      await shot(
        tester,
        'mark-256-dark.png',
        256,
        const ColoredBox(
          color: Color(0xFF0B0C10),
          child: Center(child: WowMark(size: 220)),
        ),
      );
      await shot(
        tester,
        'mark-256-light.png',
        256,
        const ColoredBox(
          color: Color(0xFFF6F5F2),
          child: Center(
            child: WowMark(
              size: 220,
              monochrome: true,
              color: Color(0xFF14161A),
            ),
          ),
        ),
      );
      await shot(
        tester,
        'strip.png',
        720,
        const ColoredBox(
          color: Color(0xFF0B0C10),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                WowMark(size: 16, tile: true),
                SizedBox(width: 18),
                WowMark(size: 32, tile: true),
                SizedBox(width: 18),
                WowMark(size: 64, tile: true),
                SizedBox(width: 18),
                WowMark(size: 128, tile: true),
              ],
            ),
          ),
        ),
        canvas: const Size(720, 200),
      );
      await shot(
        tester,
        'mark-48-monochrome.png',
        96,
        const ColoredBox(
          color: Color(0xFF101113),
          child: Center(
            child: WowMark(
              size: 48,
              monochrome: true,
              color: Color(0xFFE5EAF2),
            ),
          ),
        ),
      );
    });
  });
}
