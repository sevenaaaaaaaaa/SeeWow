import 'package:flutter/material.dart';
import 'tokens.dart';

/// One press feedback for every clickable surface: 0.965 scale + slight dim.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.scale = 0.965, this.onHoverChanged});
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final active = _down ? widget.scale : (_hover ? 1.012 : 1.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) {
        setState(() => _hover = true);
        widget.onHoverChanged?.call(true);
      },
      onExit: (_) {
        setState(() => _hover = false);
        widget.onHoverChanged?.call(false);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: active,
          duration: const Duration(milliseconds: 180),
          curve: WowMotion.snappy,
          child: AnimatedOpacity(
            opacity: _down ? 0.86 : 1,
            duration: const Duration(milliseconds: 120),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Editorial section rule: numeral — title — hairline — label.
/// The numeral and the label carry the metadata; the title carries the voice.
class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.index, required this.title, this.subtitle, this.trailing});
  final int index;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            index.toString().padLeft(2, '0'),
            style: WowType.display(30, FontWeight.w500, spacing: -0.6, height: 0.9, color: Colors.white.withValues(alpha: 0.26)),
          ),
        ),
        const SizedBox(width: 16),
        Text(title, style: WowType.display(27, FontWeight.w400, spacing: -0.6, height: 1.0)),
        const SizedBox(width: 22),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(height: 1, color: WowColors.line),
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(width: 18),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(subtitle!.toUpperCase(), style: WowType.monoLabel(9, color: WowColors.faint, spacing: 2.0)),
          ),
        ],
        if (trailing != null) ...[const SizedBox(width: 18), trailing!],
      ],
    );
  }
}