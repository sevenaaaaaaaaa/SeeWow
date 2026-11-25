import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';

/// 轨上的一种标记。三条内容轨共用一条轨，靠 [RailMarkKind] 分辨：
/// 精彩帧是短刻度、章节是长线、译配断点是虚线。
///
/// 数据不在这层：有没有章节、有没有译配断点，取决于上层给不给 [FilmRail.marks]。
/// 空列表就是一条干净的轨——不是"假装没有"，是真的没有。
enum RailMarkKind { highlight, chapter, dubbing }

class RailMark {
  const RailMark({
    required this.seconds,
    this.endSeconds,
    this.kind = RailMarkKind.highlight,
    this.label = '',
  });

  /// 起点（秒）。区间类标记（章节）拿它当左端。
  final double seconds;

  /// 区间终点（秒）。为 null 时按点标记画。
  final double? endSeconds;

  final RailMarkKind kind;
  final String label;
}

/// 轨的几何：秒与像素互算，含微距时的窗口。
///
/// 单独抽出来是为了能直接测：判据"拖到刻度落位误差 < 0.3s"测的是这个类，
/// 不是某个像素长得对不对。
@immutable
class RailGeometry {
  const RailGeometry({
    required this.width,
    required this.duration,
    this.zoom = 1,
    this.cursor = 0,
  });

  /// 微距步长：0.1 秒/像素。
  static const double fineStep = 0.1;

  final double width;
  final double duration;

  /// 1 = 整片铺满一轨。微距时是 duration / (width * fineStep)。
  final double zoom;

  /// 微距窗口的中心（秒）。zoom == 1 时不影响结果。
  final double cursor;

  bool get isFine => zoom > 1.0001;

  /// 每像素多少秒。duration 或 width 为 0 时返回 0，调用方负责不画。
  double get secondsPerPixel =>
      duration <= 0 || width <= 0 ? 0 : duration / (width * zoom);

  /// 窗口长度（秒）：整片，或整片 / zoom。
  double get windowSpan => duration <= 0 ? 0 : duration / zoom;

  double get windowStart {
    if (!isFine) return 0;
    final maxStart = math.max(0.0, duration - windowSpan);
    return (cursor - windowSpan / 2).clamp(0.0, maxStart);
  }

  double get windowEnd => windowStart + windowSpan;

  /// 秒 → 像素，钳在轨内。
  double xFor(double seconds) {
    if (secondsPerPixel <= 0) return 0;
    return ((seconds - windowStart) / secondsPerPixel).clamp(0.0, width);
  }

  /// 像素 → 秒，钳在片内。
  double timeAt(double dx) {
    if (secondsPerPixel <= 0) return 0;
    return (windowStart + dx * secondsPerPixel).clamp(0.0, duration);
  }

  bool isInside(double seconds) =>
      seconds >= windowStart && seconds <= windowEnd;

  /// 进入微距的换算：整片 1，微距 duration / (width * 0.1)。
  /// 800px 轨 + 2 小时片 → 90 倍，窗口 80 秒。
  static double zoomForFine(double duration, double width) {
    if (duration <= 0 || width <= 0) return 1;
    return math.max(1, duration / (width * fineStep));
  }
}

/// 时间码。微距要看见 0.1 秒，否则 0.1s/px 没有可观察的意义。
String formatRailTime(double seconds, {bool tenths = false}) {
  final total = seconds.isFinite ? math.max(0, seconds) : 0;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
  final ss = s.floor().toString().padLeft(2, '0');
  final tenth = ((s - s.floor()) * 10).floor();
  final head = h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  return tenths ? '$head.$tenth' : head;
}

/// 一条轨画三件事：基础轨 + 已播放 + 标记，再加 A/B 标记与游标。
///
/// 手势分两档，是这套交互的核心：
/// * 横拖 = 整片映射，手指在哪就是哪一秒；
/// * 微距 = 0.1 秒/像素。触屏长按后拖动进入，桌面按住 Option 拖动进入。
///   窗口跟着游标走，所以手指可以停在原地，刻度从手下滑过去。
class FilmRail extends StatefulWidget {
  const FilmRail({
    super.key,
    required this.duration,
    required this.position,
    required this.onSeek,
    this.marks = const [],
    this.abStart,
    this.abEnd,
    this.onPreview,
    this.onScrubStart,
    this.onScrubEnd,
    this.cursorChild,
    this.preview,
    this.height = 32,
    this.enabled = true,
  });

  /// 片长（秒）。<= 0 视为不可拖动（直播、未就绪）。
  final double duration;

  /// 当前播放点（秒）。
  final double position;

  final ValueChanged<double> onSeek;

  final List<RailMark> marks;

  final double? abStart;
  final double? abEnd;

  /// 拖动中回调"该给这一秒的图了"。缩略图的取图与缓存不在这一层。
  final ValueChanged<double>? onPreview;

  final VoidCallback? onScrubStart;
  final VoidCallback? onScrubEnd;

  /// 替换游标外观。播放页塞 SpectrumThumb 用，不传就是一条白杆。
  final Widget? cursorChild;

  /// 拖动时浮在游标上方的预览。有没有图由调用方决定：
  /// 缓存里那一桶有帧就塞 Image，没有就传 null——轨上不会出现假画面。
  final Widget? preview;

  final double height;
  final bool enabled;

  @override
  State<FilmRail> createState() => _FilmRailState();
}

class _FilmRailState extends State<FilmRail> {
  double _zoom = 1;
  double _cursor = 0;
  bool _scrubbing = false;
  double _lastX = 0;

  bool get _live => widget.enabled && widget.duration > 0;

  void _begin(double seconds) {
    if (!_live) return;
    setState(() {
      _scrubbing = true;
      _cursor = seconds;
    });
    widget.onScrubStart?.call();
    widget.onSeek(seconds);
    widget.onPreview?.call(seconds);
  }

  void _move(double seconds) {
    if (!_live) return;
    setState(() => _cursor = seconds);
    widget.onSeek(seconds);
    widget.onPreview?.call(seconds);
  }

  void _end() {
    setState(() {
      _scrubbing = false;
      _zoom = 1;
    });
    widget.onScrubEnd?.call();
  }

  /// 进微距：以按下的位置为锚点，窗口立刻收窄到 0.1 秒/像素。
  void _beginFine(double seconds, double width) {
    if (!_live) return;
    setState(() {
      _zoom = RailGeometry.zoomForFine(widget.duration, width);
      _cursor = seconds;
      _scrubbing = true;
    });
    widget.onScrubStart?.call();
    widget.onSeek(seconds);
    widget.onPreview?.call(seconds);
  }

  /// 微距：游标按 0.1 秒/像素走，窗口跟着它，手指停在原地也能继续走刻度。
  void _fineMove(double deltaPx) {
    final next = (_cursor + deltaPx * RailGeometry.fineStep)
        .clamp(0.0, widget.duration);
    _move(next);
  }

  @override
  Widget build(BuildContext context) {
    final position = _scrubbing ? _cursor : widget.position;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final geo = RailGeometry(
          width: width,
          duration: widget.duration,
          zoom: _zoom,
          cursor: position,
        );
        final cursorX = geo.xFor(position);
        final thumb = widget.cursorChild ?? const _RailThumb();
        final thumbWidth = widget.cursorChild == null ? _RailThumb.width : 44.0;

        return Semantics(
          slider: true,
          enabled: _live,
          label: '播放进度',
          value: formatRailTime(position, tenths: geo.isFine),
          // 有 increase/decrease 动作就必须同时给两个值，否则语义树在构建时断言
          // 失败（SemanticsNode.updateWith）。少一个值，整个播放页在黑屏里崩。
          increasedValue: formatRailTime(
            (position + 5).clamp(0.0, widget.duration),
            tenths: geo.isFine,
          ),
          decreasedValue: formatRailTime(
            (position - 5).clamp(0.0, widget.duration),
            tenths: geo.isFine,
          ),
          onIncrease: _live
              ? () => _move((position + 5).clamp(0.0, widget.duration))
              : null,
          onDecrease: _live
              ? () => _move((position - 5).clamp(0.0, widget.duration))
              : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _begin(geo.timeAt(d.localPosition.dx)),
            onTapUp: (_) => _end(),
            onHorizontalDragStart: (d) {
              _lastX = d.localPosition.dx;
              if (HardwareKeyboard.instance.isAltPressed) {
                _beginFine(widget.position, width);
              } else {
                _begin(geo.timeAt(d.localPosition.dx));
              }
            },
            onHorizontalDragUpdate: (d) {
              if (!_live) return;
              if (_zoom > 1.0001) {
                _fineMove(d.delta.dx);
              } else {
                _move(geo.timeAt(d.localPosition.dx));
              }
            },
            onHorizontalDragEnd: (_) => _end(),
            onHorizontalDragCancel: _end,
            onLongPressStart: (d) {
              if (!_live) return;
              _lastX = d.localPosition.dx;
              _beginFine(geo.timeAt(d.localPosition.dx), width);
              HapticFeedback.selectionClick();
            },
            onLongPressMoveUpdate: (d) {
              if (!_live || _zoom <= 1.0001) return;
              _fineMove(d.localPosition.dx - _lastX);
              _lastX = d.localPosition.dx;
            },
            onLongPressEnd: (_) => _end(),
            child: SizedBox(
              height: widget.height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _RailPainter(
                        geometry: geo,
                        position: position,
                        marks: widget.marks,
                        abStart: widget.abStart,
                        abEnd: widget.abEnd,
                        enabled: _live,
                      ),
                    ),
                  ),
                  if (geo.isFine || _scrubbing)
                    Positioned(
                      left: (cursorX - 32).clamp(
                        -(width - 64).clamp(0.0, 64.0),
                        width - 64,
                      ),
                      top: -22,
                      width: 64,
                      child: IgnorePointer(
                        child: Text(
                          formatRailTime(position, tenths: geo.isFine),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: WowColors.text,
                            fontSize: 11,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: (cursorX - thumbWidth / 2).clamp(
                      0.0,
                      math.max(0.0, width - thumbWidth),
                    ),
                    top: 0,
                    bottom: 0,
                    child: Center(child: thumb),
                  ),
                  // 预览浮在游标正上方：宽度固定，左右跟着游标走，贴到轨边就停。
                  if (widget.preview != null)
                    Positioned(
                      left: (cursorX - _previewWidth / 2).clamp(
                        0.0,
                        math.max(0.0, width - _previewWidth),
                      ),
                      bottom: widget.height + 6,
                      width: _previewWidth,
                      child: IgnorePointer(child: widget.preview),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 没有可注入的游标时用它：一根 3×16 的白杆，浅色皮肤下自动变黑。
class _RailThumb extends StatelessWidget {
  const _RailThumb();

  static const double width = 3;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: 16,
    decoration: BoxDecoration(
      color: WowColors.text,
      borderRadius: BorderRadius.circular(1.5),
    ),
  );
}

/// 预览卡宽度：160 px 的帧按 16:9 排，加 2 px 边。高度由内容自己决定。
const double _previewWidth = 168;

class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.geometry,
    required this.position,
    required this.marks,
    required this.abStart,
    required this.abEnd,
    required this.enabled,
  });

  final RailGeometry geometry;
  final double position;
  final List<RailMark> marks;
  final double? abStart;
  final double? abEnd;
  final bool enabled;

  static const double trackHeight = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final rect = Rect.fromLTWH(0, centerY - trackHeight / 2, size.width, trackHeight);
    final radius = Radius.circular(trackHeight / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = WowColors.wash(0.16),
    );

    if (enabled && geometry.duration > 0) {
      final played = geometry.xFor(position.clamp(0.0, geometry.duration));
      if (played > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(0, rect.top, played, trackHeight),
            radius,
          ),
          Paint()
            ..shader = LinearGradient(
              colors: [WowColors.accent2, WowColors.accent],
            ).createShader(Rect.fromLTWH(0, rect.top, math.max(played, 1), trackHeight)),
        );
      }
    }

    // 三条内容轨各占一个高度层，互不遮挡：章节在最上（长线、低对比），
    // 译配断点在中（虚线），精彩帧跨在基础轨上（最醒目，因为它最稀疏）。
    for (final mark in marks) {
      switch (mark.kind) {
        case RailMarkKind.chapter:
          final left = geometry.xFor(mark.seconds);
          final right = mark.endSeconds == null
              ? left
              : geometry.xFor(mark.endSeconds!);
          if (right - left < 0.5 && mark.endSeconds != null) continue;
          canvas.drawRect(
            Rect.fromLTWH(left, centerY - 7, math.max(1, right - left), 1.5),
            Paint()..color = WowColors.wash(0.34),
          );
        case RailMarkKind.dubbing:
          final x = geometry.xFor(mark.seconds);
          final paint = Paint()..color = WowColors.fade(0.55);
          for (var i = 0; i < 3; i++) {
            canvas.drawRect(
              Rect.fromLTWH(x - 4 + i * 3, centerY - 11, 1.6, 5),
              paint,
            );
          }
        case RailMarkKind.highlight:
          final x = geometry.xFor(mark.seconds);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(x - 1.5, centerY - 5, 3, 10),
              const Radius.circular(1.5),
            ),
            Paint()..color = WowColors.accent,
          );
      }
    }

    // A/B 循环画成"一段区间"，不是两根和精彩帧撞脸的竖线：
    // 区间本身铺一条淡色带，两端各一根 1.5×16 的高边。
    // 精彩帧是 3×10 的短刻度，两者靠高度和粗细分开，不靠颜色。
    // A/B 用"轨道下方的一道括号"表示区间，不用强调色：
    // 精彩帧是轨道上方的琥珀短刻度，两者既不同色也不同层，扫一眼就分得开。
    if (geometry.duration > 0) {
      final a = abStart, b = abEnd;
      final left = a == null ? null : geometry.xFor(a);
      final right = b == null ? null : geometry.xFor(b);
      if (left != null && right != null && right > left) {
        final paint = Paint()..color = WowColors.wash(0.55);
        canvas.drawRect(Rect.fromLTWH(left, centerY + 5, right - left, 1), paint);
        for (final x in [left, right]) {
          canvas.drawRect(Rect.fromLTWH(x - 0.75, centerY + 3, 1.5, 5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.position != position ||
      old.geometry.zoom != geometry.zoom ||
      old.geometry.duration != geometry.duration ||
      old.geometry.width != geometry.width ||
      old.geometry.cursor != geometry.cursor ||
      old.marks != marks ||
      old.abStart != abStart ||
      old.abEnd != abEnd ||
      old.enabled != enabled;
}
