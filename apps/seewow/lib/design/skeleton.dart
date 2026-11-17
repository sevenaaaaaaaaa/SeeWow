import 'package:flutter/material.dart';

import 'skin.dart';
import 'tokens.dart';

/// 片库首扫时的占位：给一排骨架卡，而不是一块空白或一句「片库还空着」。
///
/// 只在 `store.scanning && items.isEmpty` 时出现；已经有内容时不闪骨架，
/// 免得用户读到一半的片库被抽走。动画受系统「减弱动态效果」控制。
class LibrarySkeleton extends StatefulWidget {
  const LibrarySkeleton({
    super.key,
    required this.columns,
    this.rows = 2,
    this.animate = true,
  });
  final int columns;
  final int rows;
  final bool animate;

  @override
  State<LibrarySkeleton> createState() => _LibrarySkeletonState();
}

class _LibrarySkeletonState extends State<LibrarySkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  bool get _reduce => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _pulse.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.animate) return;
    if (_reduce) {
      _pulse.stop();
      _pulse.value = 0.6;
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SliverGrid.builder(
      itemCount: widget.columns * widget.rows,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: widget.columns,
        mainAxisSpacing: 26,
        crossAxisSpacing: 18,
        childAspectRatio: .57,
      ),
      itemBuilder: (context, index) => Semantics(
        label: '正在载入片库',
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) => Opacity(
            opacity: _reduce ? 0.7 : 0.45 + _pulse.value * 0.35,
            child: child,
          ),
          child: const _SkeletonCard(),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(WowSkin.I.spec.posterRadius),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1B1F), Color(0xFF111214)],
              ),
              border: Border.all(color: WowColors.line.withValues(alpha: 0.6)),
            ),
          ),
        ),
        const SizedBox(height: 13),
        _Bar(width: 128, height: 11),
        const SizedBox(height: 7),
        _Bar(width: 72, height: 8),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.height});
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: WowColors.line.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}
