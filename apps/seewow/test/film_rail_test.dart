import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/film_rail.dart';

/// 胶片轨的两条判据：拖到刻度落位误差、以及微距是不是真的 0.1 秒/像素。
/// 这两条都在 [RailGeometry] 上算，所以先用纯函数把它们钉死；
/// 再确认手势层把手指位置换算成同一个数。

const _w = 800.0;
const _dur = 7200.0; // 2 小时

void main() {
  group('RailGeometry', () {
    test('整片铺满：中心像素就是片长一半', () {
      const g = RailGeometry(width: _w, duration: _dur);
      expect(g.secondsPerPixel, closeTo(9.0, 1e-9));
      expect(g.timeAt(400), closeTo(3600, 1e-6));
      expect(g.xFor(3600), closeTo(400, 1e-6));
      expect(g.isFine, isFalse);
    });

    test('微距是 0.1 秒/像素，窗口 80 秒', () {
      final zoom = RailGeometry.zoomForFine(_dur, _w);
      expect(zoom, closeTo(90, 1e-9));
      final g = RailGeometry(width: _w, duration: _dur, zoom: zoom, cursor: 3600);
      expect(g.secondsPerPixel, closeTo(0.1, 1e-9));
      expect(g.windowSpan, closeTo(80, 1e-9));
      expect(g.windowStart, closeTo(3560, 1e-9));
      expect(g.timeAt(400), closeTo(3600, 1e-6));
      // 判据本身：一像素 0.1 秒，误差不靠四舍五入，靠定义。
      expect(g.timeAt(401) - g.timeAt(400), closeTo(0.1, 1e-9));
    });

    test('窗口在片头片尾不越界', () {
      final zoom = RailGeometry.zoomForFine(_dur, _w);
      expect(
        RailGeometry(width: _w, duration: _dur, zoom: zoom, cursor: 5).windowStart,
        closeTo(0, 1e-9),
      );
      expect(
        RailGeometry(width: _w, duration: _dur, zoom: zoom, cursor: _dur - 1)
            .windowStart,
        closeTo(_dur - 80, 1e-9),
      );
    });

    test('片长为 0 时不产生 NaN', () {
      const g = RailGeometry(width: _w, duration: 0);
      expect(g.timeAt(123).isNaN, isFalse);
      expect(g.xFor(123).isNaN, isFalse);
      expect(g.timeAt(123), 0);
      expect(g.xFor(123), 0);
      expect(RailGeometry.zoomForFine(0, _w), 1);
      expect(const RailGeometry(width: 0, duration: _dur).timeAt(10), 0);
    });

    test('手指落在轨外也不会跑出片子', () {
      const g = RailGeometry(width: _w, duration: _dur);
      expect(g.timeAt(-50), 0);
      expect(g.timeAt(9999), _dur);
      expect(g.xFor(-50), 0);
      expect(g.xFor(_dur + 50), _w);
    });
  });

  test('时间码：微距才显示到 0.1 秒', () {
    expect(formatRailTime(754.25), '12:34');
    expect(formatRailTime(754.25, tenths: true), '12:34.2');
    expect(formatRailTime(3661.4, tenths: true), '1:01:01.4');
    expect(formatRailTime(-3), '0:00');
  });

  group('手势', () {
    Future<void> pump(
      WidgetTester tester,
      ValueChanged<double> onSeek, {
      double duration = _dur,
      double position = 0,
      List<RailMark> marks = const [],
      double? abStart,
      double? abEnd,
      ValueChanged<double>? onPreview,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _w,
                height: 32,
                child: FilmRail(
                  duration: duration,
                  position: position,
                  onSeek: onSeek,
                  marks: marks,
                  abStart: abStart,
                  abEnd: abEnd,
                  onPreview: onPreview,
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('点中间落在片长一半，误差 < 0.3 秒', (tester) async {
      final seeks = <double>[];
      await pump(tester, seeks.add);
      await tester.tapAt(tester.getCenter(find.byType(FilmRail)));
      await tester.pump();
      expect(seeks, isNotEmpty);
      expect((seeks.last - 3600).abs(), lessThan(0.3));
    });

    testWidgets('横拖：手指在哪就是哪一秒', (tester) async {
      final seeks = <double>[];
      final previews = <double>[];
      await pump(tester, seeks.add, onPreview: previews.add);
      final topLeft = tester.getTopLeft(find.byType(FilmRail));
      final g = await tester.startGesture(
        Offset(topLeft.dx, topLeft.dy + 16),
      );
      await tester.pump();
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      await g.up();
      await tester.pump();
      // 80px * 9 秒/像素 = 720 秒
      expect((seeks.last - 720).abs(), lessThan(0.3));
      expect((previews.last - 720).abs(), lessThan(0.3));
    });

    testWidgets('长按进微距：30 像素 = 3 秒，而不是 270 秒', (tester) async {
      final seeks = <double>[];
      await pump(tester, seeks.add);
      final center = tester.getCenter(find.byType(FilmRail));
      final g = await tester.startGesture(center);
      await tester.pump(const Duration(milliseconds: 600));
      expect((seeks.last - 3600).abs(), lessThan(0.3));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      expect((seeks.last - 3603).abs(), lessThan(0.05));
      await g.up();
      await tester.pump();
      expect(seeks.last, isNotNull);
    });

    testWidgets('片长为 0：不响应，也不崩', (tester) async {
      final seeks = <double>[];
      await pump(tester, seeks.add, duration: 0);
      await tester.tapAt(tester.getCenter(find.byType(FilmRail)));
      await tester.pump();
      expect(seeks, isEmpty);
    });

    testWidgets('三条轨与 A/B 一起画不崩，空轨也不崩', (tester) async {
      await pump(
        tester,
        (_) {},
        marks: const [
          RailMark(seconds: 100),
          RailMark(seconds: 1800, kind: RailMarkKind.chapter, endSeconds: 2400),
          RailMark(seconds: 3000, kind: RailMarkKind.dubbing),
        ],
        abStart: 600,
        abEnd: 900,
      );
      await tester.pump();
      expect(find.byType(FilmRail), findsOneWidget);

      await pump(tester, (_) {});
      await tester.pump();
      expect(find.byType(FilmRail), findsOneWidget);
    });

    testWidgets('有无障碍滑杆语义', (tester) async {
      await pump(tester, (_) {});
      final semantics = tester.widgetList<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '播放进度',
        ),
      );
      expect(semantics, isNotEmpty);
      expect(semantics.first.properties.slider, isTrue);
    });
  });
}
