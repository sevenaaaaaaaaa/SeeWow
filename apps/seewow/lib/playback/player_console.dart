import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../design/liquid_glass.dart';
import '../design/tokens.dart';
import 'playback_preferences.dart';
import 'video_look.dart';

/// The shape of one spectrum frame.
///
/// The player carries a single RMS level per frame, not an FFT, so this is not
/// a frequency analysis and never claims to be one. It is an honest reading of
/// loudness shaped into bands that fall off toward the high end the way music
/// usually does, with a fixed piano-key profile so two frames of the same audio
/// always look the same.
class SpectrumShape {
  const SpectrumShape._();

  static List<double> bands(double level, {int bars = 14}) {
    final v = level.isFinite ? level.clamp(0.0, 1.0) : 0.0;
    return List<double>.generate(bars, (i) {
      final x = bars <= 1 ? 0.0 : i / (bars - 1);
      final slope = 0.42 + 0.58 * math.pow(1 - x, 0.85);
      final ripple = 0.86 + 0.14 * math.sin(i * 1.9 + 0.6);
      return (v * slope * ripple).clamp(0.0, 1.0);
    });
  }
}

/// A live spectrum meter for the console. Bars rise fast and fall slow, which
/// is what makes a meter feel like it is listening rather than animating.
class SpectrumMeter extends StatefulWidget {
  const SpectrumMeter({
    super.key,
    required this.level,
    this.bars = 14,
    this.height = 18,
    this.active = true,
    this.color,
    this.semanticLabel,
  });

  final double? level;
  final int bars;
  final double height;
  final bool active;
  final Color? color;
  final String? semanticLabel;

  @override
  State<SpectrumMeter> createState() => _SpectrumMeterState();
}

class _SpectrumMeterState extends State<SpectrumMeter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  late List<double> _shown = SpectrumShape.bands(0, bars: widget.bars);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
    if (!run) {
      _shown = SpectrumShape.bands(widget.level ?? 0, bars: widget.bars);
    }
  }

  @override
  void didUpdateWidget(SpectrumMeter old) {
    super.didUpdateWidget(old);
    if (old.bars != widget.bars) {
      _shown = SpectrumShape.bands(widget.level ?? 0, bars: widget.bars);
    }
  }

  void _tick(Duration _) {
    final target = SpectrumShape.bands(widget.level ?? 0, bars: widget.bars);
    var moved = false;
    final next = List<double>.generate(widget.bars, (i) {
      final want = target[i];
      final now = _shown[i];
      final rate = want > now ? .46 : .12;
      final value = now + (want - now) * rate;
      if ((value - now).abs() > 0.002) moved = true;
      return value.clamp(0.0, 1.0);
    });
    if (moved) setState(() => _shown = next);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? WowColors.accent;
    return Semantics(
      label: widget.semanticLabel,
      child: SizedBox(
        height: widget.height,
        child: CustomPaint(
          painter: _SpectrumPainter(values: _shown, color: color),
        ),
      ),
    );
  }
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || values.isEmpty) return;
    final slot = size.width / values.length;
    final barWidth = math.max(1.4, slot * .52);
    for (var i = 0; i < values.length; i++) {
      final h = (values[i] * size.height).clamp(1.4, size.height);
      final x = i * slot + (slot - barWidth) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - h, barWidth, h),
        Radius.circular(barWidth / 2),
      );
      final paint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: .95),
            color.withValues(alpha: .34),
          ],
        ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_SpectrumPainter old) =>
      old.color != color || old.values.length != values.length;
}

/// The AB loop, on the console where it is used instead of hidden in a menu.
///
/// One tap marks A, the next marks B and starts looping, a third clears. The
/// range stays visible as soon as A exists, so the state is never a mystery.
class AbLoopControl extends StatelessWidget {
  const AbLoopControl({
    super.key,
    required this.loop,
    required this.onMark,
    required this.onClear,
    this.enabled = true,
  });

  final AbLoop loop;
  final VoidCallback onMark;
  final VoidCallback onClear;
  final bool enabled;

  String get _hint {
    if (loop.enabled) {
      return 'AB ${playbackTime(loop.a!)}–${playbackTime(loop.b!)}';
    }
    if (loop.a != null) return 'A ${playbackTime(loop.a!)} · 再按标记 B';
    return '标记 A 点';
  }

  @override
  Widget build(BuildContext context) {
    final active = loop.enabled;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PressableLens(
          radius: 14,
          onTap: enabled ? onMark : null,
          semanticLabel: active ? 'AB 循环已开启，点击重新标记' : _hint,
          selected: active,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: active
                  ? WowColors.accent.withValues(alpha: .18)
                  : Colors.white.withValues(alpha: .06),
              border: Border.all(
                color: active
                    ? WowColors.accent.withValues(alpha: .55)
                    : Colors.white.withValues(alpha: .10),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Badge(letter: 'A', on: loop.a != null),
                const SizedBox(width: 4),
                _Badge(letter: 'B', on: loop.b != null),
                const SizedBox(width: 7),
                Text(
                  _hint,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: WowType.mono,
                    letterSpacing: .2,
                    color: active
                        ? WowColors.accent
                        : Colors.white.withValues(alpha: .70),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (loop.a != null) ...[
          const SizedBox(width: 4),
          PressableLens(
            radius: 15,
            onTap: enabled ? onClear : null,
            semanticLabel: '清除 AB 标记',
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .06),
                border: Border.all(
                  color: Colors.white.withValues(alpha: .10),
                ),
              ),
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: Colors.white.withValues(alpha: .72),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.letter, required this.on});
  final String letter;
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        color: on
            ? WowColors.accent.withValues(alpha: .92)
            : Colors.white.withValues(alpha: .10),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 9,
          height: 1,
          fontWeight: FontWeight.w700,
          color: on ? Colors.black : Colors.white.withValues(alpha: .55),
        ),
      ),
    );
  }
}

/// A row of looks. One tap applies one; the chip shows the actual grade on a
/// small strip of film, so the choice is visible before it is made.
class LookChipBar extends StatelessWidget {
  const LookChipBar({
    super.key,
    required this.current,
    required this.onSelect,
    this.looks = const [],
  });

  final VideoLook current;
  final ValueChanged<VideoLook> onSelect;
  final List<VideoLook> looks;

  @override
  Widget build(BuildContext context) {
    final list = looks.isEmpty ? VideoLook.presets : looks;
    return SizedBox(
      height: 54,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: list.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final look = list[i];
          final on = look.id == current.id;
          return PressableLens(
            radius: 13,
            onTap: () => onSelect(look),
            selected: on,
            semanticLabel: '${look.label}：${look.blurb}',
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              padding: const EdgeInsets.fromLTRB(7, 6, 9, 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(13),
                color: on
                    ? WowColors.accent.withValues(alpha: .18)
                    : Colors.white.withValues(alpha: .055),
                border: Border.all(
                  color: on
                      ? WowColors.accent.withValues(alpha: .60)
                      : Colors.white.withValues(alpha: .10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox(
                      width: 30,
                      height: 30,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(look.matrix),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFF2C27B),
                                Color(0xFFB4653C),
                                Color(0xFF243B53),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        look.label,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.2,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                          color: on ? Colors.white : Colors.white70,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'LUT',
                        style: WowType.monoLabel(
                          7.5,
                          color: on
                              ? WowColors.accent.withValues(alpha: .9)
                              : Colors.white.withValues(alpha: .34),
                          spacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
