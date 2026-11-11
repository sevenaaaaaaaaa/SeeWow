import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'playback_preferences.dart';

/// Original SeeWow entrance; animation is bounded, skippable and never owns playback.
class CinemaEntrance extends StatefulWidget {
  const CinemaEntrance({
    super.key,
    required this.style,
    required this.title,
    required this.onComplete,
  });
  final EntranceStyle style;
  final String title;
  final VoidCallback onComplete;
  @override
  State<CinemaEntrance> createState() => _CinemaEntranceState();
}

class _CinemaEntranceState extends State<CinemaEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2100),
  );
  bool _started = false, _completed = false;
  @override
  void initState() {
    super.initState();
    _animation.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.style == EntranceStyle.none ||
        MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
    } else {
      _animation.forward();
    }
  }

  void _finish() {
    if (_completed) return;
    _completed = true;
    _animation.stop();
    widget.onComplete();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xff06070a),
    child: SafeArea(
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                final t = Curves.easeInOutCubic.transform(_animation.value);
                final fade = ((1 - t) / .18).clamp(0.0, 1.0);
                return Opacity(
                  opacity: fade,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.style == EntranceStyle.disc)
                        Transform.rotate(
                          angle: t * math.pi * 3,
                          child: Transform.scale(
                            scale: .7 + t * .35,
                            child: CustomPaint(
                              size: const Size(190, 190),
                              painter: _DiscPainter(t),
                            ),
                          ),
                        )
                      else
                        Transform.scale(
                          scale: .84 + t * .22,
                          child: ShaderMask(
                            shaderCallback: (r) => LinearGradient(
                              begin: Alignment(-2 + t * 4, -1),
                              end: Alignment(t * 4, 1),
                              colors: const [
                                Colors.white38,
                                Colors.white,
                                Color(0xffc3b1ff),
                                Colors.white38,
                              ],
                            ).createShader(r),
                            child: const Text(
                              'SeeWow',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 58,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3,
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 30),
                      if (widget.style == EntranceStyle.disc)
                        const Text(
                          'SeeWow',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            letterSpacing: 5,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 30),
                        child: Text(
                          widget.title,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        '为这一刻，留一束光',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          letterSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: TextButton(
              onPressed: _finish,
              child: const Text(
                '跳过片头',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _DiscPainter extends CustomPainter {
  _DiscPainter(this.progress);
  final double progress;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero), r = size.width / 2;
    final paint = Paint()
      ..shader = const SweepGradient(
        colors: [
          Color(0xff191c29),
          Color(0xffc2b8f5),
          Color(0xff323c53),
          Color(0xff82aebd),
          Color(0xff161925),
          Color(0xffa69bb9),
          Color(0xff191c29),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawCircle(center, r, paint);
    for (var i = 0; i < 14; i++) {
      canvas.drawCircle(
        center,
        r * (.3 + i * .047),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = Colors.white.withValues(alpha: .08)
          ..strokeWidth = .6,
      );
    }
    canvas.drawCircle(
      center,
      r * .17,
      Paint()..color = const Color(0xff06070a),
    );
    canvas.drawCircle(
      center,
      r * .18,
      Paint()
        ..color = Colors.white38
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_DiscPainter oldDelegate) => false;
}
