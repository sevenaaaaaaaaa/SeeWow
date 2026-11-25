import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One tap on the console turns the picture into another medium.
///
/// A look is a grade (a 4x5 colour matrix) plus an optional physical overlay:
/// scanlines, grain, gate weave, flicker, bloom, vignette. Everything is drawn
/// in Flutter, so a look costs nothing at install time and works on every
/// platform, including the ones where libmpv has no shader pipeline.
///
/// Honest limits: the overlays are filters over the rendered frame, not a
/// decode-path tone map. A look changes how the picture reads; it cannot add
/// highlight detail the source does not carry, and Dolby and OLED here are
/// grades in that spirit rather than licensed metadata pipelines.
class VideoLook {
  const VideoLook({
    required this.id,
    required this.label,
    required this.blurb,
    required this.icon,
    required this.matrix,
    this.scanlines = 0,
    this.grain = 0,
    this.vignette = 0,
    this.flicker = 0,
    this.weave = 0,
    this.bloom = 0,
  });

  final String id;

  /// Short name on the chip.
  final String label;

  /// One line that says what the grade actually does.
  final String blurb;
  final IconData icon;
  final List<double> matrix;

  /// Strength of each physical overlay, 0 to 1 (weave is pixels).
  final double scanlines;
  final double grain;
  final double vignette;
  final double flicker;
  final double weave;
  final double bloom;

  bool get touchesPixels =>
      scanlines > 0 ||
      grain > 0 ||
      vignette > 0 ||
      flicker > 0 ||
      weave > 0 ||
      bloom > 0;

  static VideoLook byId(String? id) =>
      presets.where((look) => look.id == id).firstOrNull ?? native;

  static const native = VideoLook(
    id: 'native',
    label: '原色',
    blurb: '不做任何处理，画面就是片源本身',
    icon: Icons.circle_outlined,
    matrix: _identity,
  );

  /// 原色 + 十三款画风，顺序就是控制台里的排列顺序。
  static final List<VideoLook> presets = [
    native,
    VideoLook(
      id: 'crt',
      label: '显像管',
      blurb: '扫描线、荧光染色与圆角晕影，像一台调准了的 CRT',
      icon: Icons.tv_rounded,
      matrix: grade(contrast: 1.12, sat: 1.18, tint: [0.98, 1.02, 1.07]),
      scanlines: .20,
      vignette: .34,
      bloom: .12,
    ),
    VideoLook(
      id: 'cinema',
      label: '电影院',
      blurb: '暗部偏青、高光偏暖，加一层很淡的颗粒',
      icon: Icons.theaters_rounded,
      matrix: grade(
        contrast: 1.06,
        sat: 1.04,
        tint: [1.05, 1.0, 0.95],
        lift: [-0.012, 0.0, 0.02],
      ),
      vignette: .26,
      grain: .03,
    ),
    VideoLook(
      id: 'film',
      label: '老电影',
      blurb: '褪色偏棕、胶片颗粒、轻微闪烁与片门晃动',
      icon: Icons.movie_filter_rounded,
      matrix: grade(
        contrast: 1.02,
        sat: 0.42,
        tint: [1.14, 1.01, 0.84],
        lift: [0.05, 0.03, 0.0],
      ),
      grain: .15,
      flicker: .045,
      weave: 1.1,
      vignette: .40,
    ),
    VideoLook(
      id: 'dolby',
      label: '杜比',
      blurb: '拉高高光与对比，中心提亮，模拟 HDR 的光感',
      icon: Icons.hdr_strong_rounded,
      matrix: grade(contrast: 1.18, sat: 1.12, lift: [-0.008, -0.008, -0.008]),
      bloom: .20,
      vignette: .12,
    ),
    VideoLook(
      id: 'oled',
      label: 'OLED',
      blurb: '压黑提纯，暗场直接归零，颜色更饱和',
      icon: Icons.dark_mode_rounded,
      matrix: grade(contrast: 1.28, sat: 1.08, lift: [-0.035, -0.035, -0.035]),
    ),
    VideoLook(
      id: 'ink',
      label: '墨水',
      blurb: '去掉颜色，只留纸面灰阶与一点纸纹',
      icon: Icons.brush_rounded,
      matrix: grade(contrast: 1.16, sat: 0.0, lift: [0.015, 0.015, 0.015]),
      grain: .05,
      vignette: .16,
    ),
    VideoLook(
      id: 'anime',
      label: '动漫',
      blurb: '饱和与对比同时抬高，边缘更利，像赛璐珞上色',
      icon: Icons.auto_awesome_rounded,
      matrix: grade(contrast: 1.10, sat: 1.42, lift: [0.008, 0.0, 0.012]),
      bloom: .06,
    ),
    // 白皙系：把肤色抬亮、压低一点对比，同时用极轻的染色给冷暖方向。
    VideoLook(
      id: 'coolwhite',
      label: '冷白',
      blurb: '肤色抬亮、整体往冷里推一点，像阴天里的白瓷',
      icon: Icons.ac_unit_rounded,
      matrix: grade(
        contrast: 1.06,
        sat: .90,
        tint: [.965, 1.0, 1.07],
        lift: [.022, .024, .034],
      ),
    ),
    VideoLook(
      id: 'pinkwhite',
      label: '粉白',
      blurb: '皮肤粉里透红：提亮的同时把红留住，气色比原片好一层',
      icon: Icons.spa_rounded,
      matrix: grade(
        contrast: 1.04,
        sat: 1.06,
        tint: [1.055, .99, 1.005],
        lift: [.03, .012, .02],
      ),
    ),
    // 三种动画：靠串扰分开——国漫的青玉阴影、日漫的干净高光、
    // 美漫的压死黑位，只调对比度是做不出差别的。
    VideoLook(
      id: 'guoman',
      label: '国漫',
      blurb: '奶白的黑位、青玉阴影，像水墨落在宣纸上',
      icon: Icons.landscape_rounded,
      matrix: grade(
        contrast: .99,
        sat: 1.14,
        tint: [1.0, 1.005, 1.01],
        lift: [.045, .05, .048],
        mix: [
          [.97, .03, 0],
          [.02, .96, .05],
          [0, .08, .93],
        ],
      ),
    ),
    VideoLook(
      id: 'riiman',
      label: '日漫',
      blurb: '干净的赛璐珞：饱和拉满、高光偏冷、黑位收紧',
      icon: Icons.brightness_5_rounded,
      matrix: grade(
        contrast: 1.12,
        sat: 1.34,
        lift: [.004, .006, .012],
        mix: [
          [1, 0, 0],
          [0, .99, .01],
          [.01, .02, 1],
        ],
      ),
    ),
    VideoLook(
      id: 'meiman',
      label: '美漫',
      blurb: '黑位压到底、原色更凶，像印在铜版纸上的分镜',
      icon: Icons.flash_on_rounded,
      matrix: grade(
        contrast: 1.22,
        sat: 1.38,
        lift: [-.026, -.026, -.024],
        mix: [
          [1.03, -.02, 0],
          [.01, .99, 0],
          [0, .02, .98],
        ],
      ),
      vignette: .18,
    ),
    VideoLook(
      id: 'kon',
      label: '今敏',
      blurb: '洋红影子配躁动的红，梦里那层不真实的高对比',
      icon: Icons.blur_on_rounded,
      matrix: grade(
        contrast: 1.16,
        sat: 1.22,
        lift: [-.012, -.004, .008],
        mix: [
          [1.04, 0, .03],
          [-.01, .98, .02],
          [.05, 0, .98],
        ],
      ),
      vignette: .22,
      grain: .02,
    ),
  ];

  /// Composes a look's grade. Matrix offsets are in the 0-255 space Flutter
  /// expects, which is why the lift is multiplied at the end.
  static List<double> grade({
    double contrast = 1,
    double sat = 1,
    List<double> tint = const [1, 1, 1],
    List<double> lift = const [0, 0, 0],
    List<List<double>>? mix,
  }) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final a = lr * (1 - sat), b = lg * (1 - sat), c = lb * (1 - sat);
    final k = contrast;
    final m = <double>[
      (a + sat) * k * tint[0],
      b * k * tint[0],
      c * k * tint[0],
      0,
      0,
      a * k * tint[1],
      (b + sat) * k * tint[1],
      c * k * tint[1],
      0,
      0,
      a * k * tint[2],
      b * k * tint[2],
      (c + sat) * k * tint[2],
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ];
    if (mix != null) {
      // 3x3 串扰：把某个通道的能量漏给另一个通道。它是唯一能让
      // 「暗部偏青、亮部偏暖」这种分级在纯矩阵里成立的项。
      final rows = [
        [m[0], m[1], m[2]],
        [m[5], m[6], m[7]],
        [m[10], m[11], m[12]],
      ];
      const slots = [0, 1, 2, 5, 6, 7, 10, 11, 12];
      for (var r = 0; r < 3; r++) {
        for (var c = 0; c < 3; c++) {
          var v = 0.0;
          for (var k2 = 0; k2 < 3; k2++) {
            v += rows[r][k2] * mix[k2][c];
          }
          m[slots[r * 3 + c]] = v;
        }
      }
    }
    final base = (1 - k) * 0.5;
    m[4] = (base + lift[0]) * 255;
    m[9] = (base + lift[1]) * 255;
    m[14] = (base + lift[2]) * 255;
    return m;
  }

  static const List<double> _identity = [
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// Wraps the picture in the selected look. Switching does not cut: a short
/// optical flash covers the moment the grade changes, which reads as the lens
/// adapting instead of the frame jumping.
class VideoLookView extends StatefulWidget {
  const VideoLookView({
    super.key,
    required this.look,
    required this.child,
    this.enabled = true,
  });

  final VideoLook look;
  final Widget child;
  final bool enabled;

  @override
  State<VideoLookView> createState() => _VideoLookViewState();
}

class _VideoLookViewState extends State<VideoLookView>
    with TickerProviderStateMixin {
  late final AnimationController _grain = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _switch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(VideoLookView old) {
    super.didUpdateWidget(old);
    if (old.look.id != widget.look.id) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _switch.value = 1;
      } else {
        _switch.forward(from: 0);
      }
    }
    _sync();
  }

  void _sync() {
    final run =
        widget.enabled &&
        widget.look.touchesPixels &&
        !MediaQuery.disableAnimationsOf(context);
    if (run && !_grain.isAnimating) {
      _grain.repeat();
    } else if (!run && _grain.isAnimating) {
      _grain.stop();
    }
  }

  @override
  void dispose() {
    _grain.dispose();
    _switch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    if (!widget.enabled || look.id == VideoLook.native.id) {
      return widget.child;
    }
    Widget picture = ColorFiltered(
      colorFilter: ColorFilter.matrix(look.matrix),
      child: widget.child,
    );
    if (look.weave > 0) {
      picture = AnimatedBuilder(
        animation: _grain,
        builder: (context, child) => Transform.translate(
          offset: Offset(
            math.sin(_grain.value * math.pi * 2) * look.weave,
            math.cos(_grain.value * math.pi * 2 * 1.7) * look.weave * .5,
          ),
          child: child,
        ),
        child: picture,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        picture,
        if (look.touchesPixels)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _grain,
                builder: (context, _) => CustomPaint(
                  painter: LookPainter(look: look, t: _grain.value),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _switch,
              builder: (context, _) => ColoredBox(
                color: Color.fromRGBO(255, 255, 255, (1 - _switch.value) * .12),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Draws the physical part of a look. Kept public so a test can render it
/// without a player.
class LookPainter extends CustomPainter {
  LookPainter({required this.look, required this.t});

  final VideoLook look;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;

    if (look.bloom > 0) {
      final bloom = Paint()
        ..blendMode = BlendMode.plus
        ..shader =
            RadialGradient(
              colors: [
                Colors.white.withValues(alpha: look.bloom * .22),
                Colors.white.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(
                center: rect.center,
                radius: math.max(size.width, size.height) * .58,
              ),
            );
      canvas.drawRect(rect, bloom);
    }

    if (look.scanlines > 0) {
      final line = Paint()
        ..color = Colors.black.withValues(alpha: look.scanlines);
      final step = 2.6 + (size.height / 900).clamp(0.0, 1.4);
      for (var y = 0.0; y < size.height; y += step * 2) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, step), line);
      }
    }

    if (look.grain > 0) {
      final rng = math.Random((t * 240).floor() + 17);
      final dot = Paint();
      final count = (size.width * size.height / 2600).clamp(200, 5000).round();
      for (var i = 0; i < count; i++) {
        final x = rng.nextDouble() * size.width;
        final y = rng.nextDouble() * size.height;
        dot.color = (rng.nextBool() ? Colors.white : Colors.black).withValues(
          alpha: look.grain * (.06 + rng.nextDouble() * .12),
        );
        canvas.drawRect(Rect.fromLTWH(x, y, 1.4, 1.4), dot);
      }
    }

    if (look.vignette > 0) {
      final shade = Paint()
        ..shader = RadialGradient(
          radius: .82,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: look.vignette),
          ],
          stops: const [.55, 1],
        ).createShader(rect);
      canvas.drawRect(rect, shade);
    }

    if (look.flicker > 0) {
      final swing = (math.sin(t * math.pi * 2 * 7) + 1) * .5;
      canvas.drawRect(
        rect,
        Paint()..color = Colors.white.withValues(alpha: look.flicker * swing),
      );
    }
  }

  @override
  bool shouldRepaint(LookPainter old) => old.t != t || old.look.id != look.id;
}
