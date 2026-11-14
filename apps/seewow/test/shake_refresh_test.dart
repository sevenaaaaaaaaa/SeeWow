import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/app/shake_refresh.dart';

void main() {
  group('ReversalShakeDetector', () {
    test('one long sweep is not a shake', () {
      final detector = ReversalShakeDetector();
      final t = DateTime(2026, 1, 1, 12);
      expect(detector.add(0, t), isFalse);
      expect(detector.add(100, t.add(const Duration(milliseconds: 50))), isFalse);
      expect(detector.add(200, t.add(const Duration(milliseconds: 100))), isFalse);
    });

    test('three direction changes inside the window fire once', () {
      final detector = ReversalShakeDetector();
      final t = DateTime(2026, 1, 1, 12);
      final values = <double>[0, 80, 0, 80, 0];
      var fired = false;
      for (var i = 0; i < values.length; i++) {
        fired = detector.add(
          values[i],
          t.add(Duration(milliseconds: 40 * i)),
        );
      }
      expect(fired, isTrue);
    });

    test('movement below the amplitude floor never counts', () {
      final detector = ReversalShakeDetector(minAmplitude: 40);
      final t = DateTime(2026, 1, 1, 12);
      var fired = false;
      for (var i = 0; i < 20; i++) {
        fired |= detector.add(
          i.isEven ? 0 : 20,
          t.add(Duration(milliseconds: 30 * i)),
        );
      }
      expect(fired, isFalse);
    });

    test('reversals spread beyond the window are forgotten', () {
      final detector = ReversalShakeDetector(
        window: const Duration(milliseconds: 300),
      );
      final t = DateTime(2026, 1, 1, 12);
      expect(detector.add(0, t), isFalse);
      expect(
        detector.add(100, t.add(const Duration(milliseconds: 100))),
        isFalse,
      );
      expect(
        detector.add(0, t.add(const Duration(milliseconds: 1000))),
        isFalse,
      );
      expect(
        detector.add(100, t.add(const Duration(milliseconds: 2000))),
        isFalse,
      );
    });

    test('a slow sample stream still needs a real back-and-forth', () {
      // 5 Hz is the sensors_plus default. Four samples are enough to make
      // three reversals, so the detector works at that rate — but a single
      // sweep must not fire.
      final detector = ReversalShakeDetector(minAmplitude: 14);
      final t = DateTime(2026, 1, 1, 12);
      expect(detector.add(0, t), isFalse);
      expect(detector.add(40, t.add(const Duration(milliseconds: 200))), isFalse);
      expect(detector.add(80, t.add(const Duration(milliseconds: 400))), isFalse);
      expect(detector.add(120, t.add(const Duration(milliseconds: 600))), isFalse);
    });

    test('a second shake respects the cooldown', () {
      final detector = ReversalShakeDetector();
      final t = DateTime(2026, 1, 1, 12);
      bool shake(DateTime start) {
        var fired = false;
        for (var i = 0; i < 5; i++) {
          fired = detector.add(
            i.isEven ? 0 : 90,
            start.add(Duration(milliseconds: 40 * i)),
          );
        }
        return fired;
      }

      expect(shake(t), isTrue);
      expect(shake(t.add(const Duration(milliseconds: 600))), isFalse);
      expect(shake(t.add(const Duration(seconds: 4))), isTrue);
    });
  });

  group('RefreshGestureGate', () {
    test('a playing film blocks the gesture', () {
      final gate = RefreshGestureGate();
      expect(gate.armed, isTrue);
      gate.playing = true;
      expect(gate.armed, isFalse);
      gate.playing = false;
      expect(gate.armed, isFalse, reason: 'just stopped, still too soon');
    });

    test('a tap blocks the gesture for the idle window only', () {
      var now = DateTime(2026, 1, 1, 12);
      final gate = RefreshGestureGate(clock: () => now);
      gate.markInteraction();
      expect(gate.armed, isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(gate.armed, isFalse);
      now = now.add(const Duration(seconds: 2));
      expect(gate.armed, isTrue);
    });
  });

  group('shakeSurfaceFor', () {
    test('phone uses the accelerometer, desktop shakes the window', () {
      expect(
        shakeSurfaceFor(isMobile: true, isDesktop: false, sensorsAvailable: true),
        ShakeSurface.accelerometer,
      );
      expect(
        shakeSurfaceFor(isMobile: false, isDesktop: true, sensorsAvailable: false),
        ShakeSurface.window,
      );
      expect(
        shakeSurfaceFor(isMobile: false, isDesktop: false, sensorsAvailable: false),
        ShakeSurface.none,
      );
    });
  });

  test('the gate never lets a shake fire while the controller is refreshing', () async {
    final gate = RefreshGestureGate();
    var calls = 0;
    final controller = ShakeRefreshController(
      gate: gate,
      onRefresh: () async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
    );
    final t = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < 5; i++) {
      await controller.feed(i.isEven ? 0 : 90, t.add(Duration(milliseconds: 40 * i)));
    }
    expect(calls, 1);
    controller.dispose();
  });
}
