import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/video_look.dart';

/// 把六款新画风压在同一块取样板上，出图给用户看。
/// 播放器是平台视图截不到，但画风本身只是颜色矩阵，可以离屏渲染。
class _LookCell extends StatelessWidget {
  const _LookCell({
    required this.look,
    required this.color,
    required this.size,
  });
  final VideoLook look;
  final Color color;
  final Size size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size.width,
    height: size.height,
    child: ColorFiltered(
      colorFilter: ColorFilter.matrix(look.matrix),
      child: ColoredBox(color: color),
    ),
  );
}

void main() {
  setUpAll(() async {
    // 中文标签要有字体，否则整张图只有色块。
    final file = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (await file.exists()) {
      final loader = FontLoader('SheetFont')
        ..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
      await loader.load();
    }
  });

  testWidgets('look sheet shot', (tester) async {
    final key = GlobalKey();
    const ids = [
      'native',
      'coolwhite',
      'pinkwhite',
      'guoman',
      'riiman',
      'meiman',
      'kon',
    ];
    const samples = <String, Color>{
      '肤色': Color.fromARGB(255, 222, 173, 141),
      '天光': Color.fromARGB(255, 120, 170, 220),
      '草木': Color.fromARGB(255, 70, 120, 60),
      '暗部': Color.fromARGB(255, 30, 34, 42),
    };
    const cell = Size(148, 92);
    const labelWidth = 84.0;

    tester.view.physicalSize = const Size(1200, 560);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Widget header() => Row(
      children: [
        const SizedBox(width: labelWidth),
        for (final id in ids)
          SizedBox(
            width: cell.width,
            height: 34,
            child: Center(
              child: Text(
                VideoLook.byId(id).label,
                style: const TextStyle(
                  fontFamily: 'SheetFont',
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFF0B0B0D),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '画风取样板 · 原色 + 六款新画风',
                  style: TextStyle(
                    fontFamily: 'SheetFont',
                    fontSize: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                header(),
                for (final entry in samples.entries)
                  Row(
                    children: [
                      SizedBox(
                        width: labelWidth,
                        height: cell.height,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            entry.key,
                            style: const TextStyle(
                              fontFamily: 'SheetFont',
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                      ),
                      for (final id in ids)
                        Padding(
                          padding: const EdgeInsets.only(right: 4, bottom: 4),
                          child: _LookCell(
                            look: VideoLook.byId(id),
                            color: entry.value,
                            size: cell,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final out = File('../../docs/screens/look-2026-11-25-sheet.png');
    out.parent.createSync(recursive: true);
    out.writeAsBytesSync(bytes!);
    debugPrint('shot look-sheet (${bytes.length} bytes) -> ${out.path}');
    expect(bytes.length, greaterThan(2000));
  });
}
