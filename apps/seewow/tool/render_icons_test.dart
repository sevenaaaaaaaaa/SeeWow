// ignore_for_file: avoid_print, prefer_interpolation_to_compose_strings
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/design/brand_mark.dart';

/// Draws every app icon this repository ships, straight from the mark.
///
///   flutter test tool/render_icons_test.dart
///
/// iOS and Android get opaque RGB PNGs: both stores reject an icon with an
/// alpha channel, and Flutter's encoder always writes RGBA. macOS keeps its
/// alpha, because a macOS icon is a rounded shape on a transparent card.
void main() {
  final repo = Directory.current.parent.parent.path; // apps/seewow -> repo
  final iosDir =
      repo + '/apps/seewow/ios/Runner/Assets.xcassets/AppIcon.appiconset';
  final macDir =
      repo + '/apps/seewow/macos/Runner/Assets.xcassets/AppIcon.appiconset';
  final androidRes = repo + '/apps/seewow/android/app/src/main/res';

  Future<ui.Image> shot(WidgetTester tester, double size, Widget child) async {
    await tester.binding.setSurfaceSize(Size(size, size));
    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: SizedBox(width: size, height: size, child: child),
        ),
      ),
    );
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return boundary.toImage(pixelRatio: 1);
  }

  Future<void> writeRgb(ui.Image image, String path) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final raw = data!.buffer.asUint8List();
    final w = image.width, h = image.height;
    final scan = Uint8List(h * (1 + w * 3));
    var p = 0;
    for (var y = 0; y < h; y++) {
      scan[p++] = 0;
      for (var x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        scan[p++] = raw[i];
        scan[p++] = raw[i + 1];
        scan[p++] = raw[i + 2];
      }
    }
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(_png(w, h, scan));
  }

  testWidgets('write app icons', (tester) async {
    await tester.runAsync(() async {
      // iOS: full-bleed square, opaque.
      const ios = <int, String>{
        20: 'Icon-App-20x20@1x.png',
        40: 'Icon-App-20x20@2x.png',
        60: 'Icon-App-20x20@3x.png',
        29: 'Icon-App-29x29@1x.png',
        58: 'Icon-App-29x29@2x.png',
        87: 'Icon-App-29x29@3x.png',
        80: 'Icon-App-40x40@2x.png',
        120: 'Icon-App-40x40@3x.png',
        180: 'Icon-App-60x60@3x.png',
        76: 'Icon-App-76x76@1x.png',
        152: 'Icon-App-76x76@2x.png',
        167: 'Icon-App-83.5x83.5@2x.png',
        1024: 'Icon-App-1024x1024@1x.png',
      };
      for (final entry in ios.entries) {
        final image = await shot(
          tester,
          entry.key.toDouble(),
          WowMark(size: entry.key.toDouble(), tile: true, tileRadius: 0),
        );
        await writeRgb(image, iosDir + '/' + entry.value);
        print('ios ' + entry.value);
      }

      // iOS also carries a 40 and a 120 under other names; they are the same
      // pixels, so copy rather than re-render.
      await writeRgb(
        await shot(tester, 40, const WowMark(size: 40, tile: true, tileRadius: 0)),
        iosDir + '/Icon-App-40x40@1x.png',
      );
      await writeRgb(
        await shot(tester, 120, const WowMark(size: 120, tile: true, tileRadius: 0)),
        iosDir + '/Icon-App-60x60@2x.png',
      );

      // macOS: squircle on transparency.
      for (final size in [16, 32, 64, 128, 256, 512, 1024]) {
        final image = await shot(
          tester,
          size.toDouble(),
          WowMark(size: size.toDouble(), tile: true),
        );
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(macDir + '/app_icon_' + size.toString() + '.png');
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        print('macos ' + size.toString());
      }

      // Android legacy launchers.
      const android = <String, int>{
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192,
      };
      for (final entry in android.entries) {
        final image = await shot(
          tester,
          entry.value.toDouble(),
          WowMark(size: entry.value.toDouble(), tile: true, tileRadius: .2237),
        );
        await writeRgb(image, androidRes + '/' + entry.key + '/ic_launcher.png');
        print('android ' + entry.key);
      }

      // A copy for the docs, at full size.
      final hero = await shot(tester, 1024, const WowMark(size: 1024, tile: true));
      final bytes = await hero.toByteData(format: ui.ImageByteFormat.png);
      await File(repo + '/docs/screens/brand-mark-1024.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      print('docs brand-mark-1024.png');
    });
  });
}

/// Minimal PNG writer for 8-bit RGB (no alpha channel, which is the point).
Uint8List _png(int width, int height, Uint8List scanlines) {
  final builder = BytesBuilder();
  builder.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 2)
    ..setUint8(10, 0)
    ..setUint8(11, 0)
    ..setUint8(12, 0);
  builder.add(_chunk('IHDR', ihdr.buffer.asUint8List()));
  builder.add(_chunk('IDAT', ZLibEncoder().convert(scanlines)));
  builder.add(_chunk('IEND', Uint8List(0)));
  return builder.toBytes();
}

List<int> _chunk(String type, List<int> data) {
  final body = <int>[...type.codeUnits, ...data];
  final out = BytesBuilder();
  out.add((ByteData(4)..setUint32(0, data.length)).buffer.asUint8List());
  out.add(body);
  out.add((ByteData(4)..setUint32(0, _crc(body))).buffer.asUint8List());
  return out.toBytes();
}

int _crc(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final b in bytes) {
    crc ^= b;
    for (var k = 0; k < 8; k++) {
      crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >> 1)) : (crc >> 1);
    }
  }
  return crc ^ 0xFFFFFFFF;
}
