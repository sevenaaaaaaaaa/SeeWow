import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 进度条上的频谱游标：一组竖条，跟着播放点走。
///
/// 数据来自 [SpectrumAnalysis] 对当前帧 PCM 的 FFT（见 AudioLevel.bands），
/// 不是把单一电平塑形成阶梯的那种假频谱。拿不到频段时（暂停、译配中、采样
/// 失败）退回一个白点，保证「能抓住游标拖动」这件事永远成立。
class SpectrumThumb extends StatelessWidget {
  const SpectrumThumb({
    super.key,
    required this.bands,
    this.bars = 9,
    this.height = 28,
  });

  final List<double> bands;
  final int bars;
  final double height;

  static const double barWidth = 2.4, gap = 2, padX = 3, padY = 3;

  /// 宽度固定，进度条的定位才算得出来，不必等布局。
  static const double width = 44;

  static const double _idleDiameter = 12;

  /// 把任意长度的频段重采样成 [bars] 根：区间取最大值，瞬态不被平均掉。
  static List<double> heights(List<double> source, int bars) {
    if (bars <= 0) return const [];
    if (source.isEmpty) return List<double>.filled(bars, 0);
    return List<double>.generate(bars, (i) {
      final from = (i * source.length / bars).floor();
      final to = math.max(from + 1, ((i + 1) * source.length / bars).ceil());
      var peak = 0.0;
      for (var k = from; k < to && k < source.length; k++) {
        final v = source[k];
        if (v.isFinite && v > peak) peak = v;
      }
      return peak.clamp(0.0, 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (bands.isEmpty) {
      return const SizedBox(
        width: width,
        height: 16,
        child: Center(
          child: SizedBox(
            width: _idleDiameter,
            height: _idleDiameter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }
    final values = heights(bands, bars);
    final style = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: padX, vertical: padY),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .58),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < bars; i++)
            _bar(i, values[i], style, active: i == bars ~/ 2),
        ],
      ),
    );
  }

  Widget _bar(int index, double value, bool reduce, {required bool active}) {
    // 上下边框各 1px：算高度时先扣掉，否则满能量的竖条会被裁掉 2px。
    final usable = height - padY * 2 - 2;
    final h = 2 + value * (usable - 2);
    return TweenAnimationBuilder<double>(
      key: ValueKey('spectrumBar.$index'),
      tween: Tween(begin: h, end: h),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      builder: (_, v, _) => Container(
        width: barWidth,
        height: v,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? .96 : .74),
          borderRadius: BorderRadius.circular(1.2),
        ),
      ),
    );
  }
}
