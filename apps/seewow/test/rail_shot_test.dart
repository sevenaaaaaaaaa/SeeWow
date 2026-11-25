import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/film_rail.dart';

/// 胶片轨的三态留档图。跑：
///   flutter test test/rail_shot_test.dart
/// 输出：docs/design/shots-2026-11-25/rail-states.png
///
/// 不做 golden 比较：字体与渲染在不同机器上会差一两个像素，比较只会制造噪声。
/// 这张图的用途是让人一眼看出三条轨、微距窗口和空轨各长什么样。
void main() {
  // 字体必须在 setUpAll 里读：testWidgets 的假时钟不会推进真实文件 IO，
  // 写进测试体会直接挂住（等 10 分钟然后超时）。
  setUpAll(() async {
    final fontFile = File('/System/Library/Fonts/Supplemental/Arial Unicode.ttf');
    if (await fontFile.exists()) {
      final loader = FontLoader('ShotFont')
        ..addFont(
          Future.value(ByteData.sublistView(await fontFile.readAsBytes())),
        );
      await loader.load();
    }
  });

  testWidgets('rail states shot', (tester) async {
    tester.view.physicalSize = const Size(1760, 1000);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    final labelStyle = TextStyle(
      fontFamily: 'ShotFont',
      color: Colors.white.withValues(alpha: .45),
      fontSize: 11,
      letterSpacing: .4,
    );

    const marks = [
      RailMark(seconds: 320),
      RailMark(seconds: 1180),
      RailMark(seconds: 2410),
      RailMark(seconds: 3020),
      RailMark(seconds: 420, kind: RailMarkKind.chapter, endSeconds: 1100),
      RailMark(seconds: 1180, kind: RailMarkKind.chapter, endSeconds: 2380),
      RailMark(seconds: 2410, kind: RailMarkKind.chapter, endSeconds: 3500),
      RailMark(seconds: 1500, kind: RailMarkKind.dubbing),
      RailMark(seconds: 2760, kind: RailMarkKind.dubbing),
    ];

    Widget row(String tag, Widget rail) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tag, style: labelStyle),
          const SizedBox(height: 8),
          SizedBox(width: 800, height: 32, child: rail),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // 整棵树都用真字体，否则轨上的时间码也是方块。
        theme: ThemeData(fontFamily: 'ShotFont'),
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF0B0B0C),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: DefaultTextStyle(
                style: const TextStyle(fontFamily: 'ShotFont'),
                child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  row(
                    'full film  ·  2h  ·  highlights / chapters / dubbing / A-B',
                    FilmRail(
                      duration: 7200,
                      position: 2760,
                      marks: marks,
                      abStart: 1180,
                      abEnd: 2380,
                      onSeek: (_) {},
                    ),
                  ),
                  // 预览卡是浮在轨上方出界的，给它 104 px 的空中位置，
                  // 否则会压到上一行的轨道上（真播放器里那块是画面，不会撞）。
                  const SizedBox(height: 104),
                  row(
                    'fine  ·  held, 0.1 s/px window  ·  trickplay preview',
                    FilmRail(
                      duration: 7200,
                      position: 3600,
                      onSeek: (_) {},
                      preview: Container(
                        width: 168,
                        height: 94,
                        decoration: BoxDecoration(
                          color: const Color(0xFF23201C),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .18),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '00:60',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .55),
                            fontSize: 12,
                            fontFamily: 'ShotFont',
                          ),
                        ),
                      ),
                    ),
                  ),
                  row(
                    'empty  ·  no bookmarks, no chapters, no dubbing',
                    FilmRail(duration: 7200, position: 900, onSeek: (_) {}),
                  ),
                ],
              ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // 第二态：真按住进微距，不是摆拍一个参数。
    final railFinder = find.byType(FilmRail).at(1);
    final center = tester.getCenter(railFinder);
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    final outDir = Directory('../../docs/design/shots-2026-11-25')
      ..createSync(recursive: true);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    final file = File('${outDir.path}/rail-states.png');
    file.writeAsBytesSync(bytes!);
    // ignore: avoid_print
    print('shot ${file.absolute.path} (${bytes.length} bytes)');

    await gesture.up();
    await tester.pump();
  });
}
