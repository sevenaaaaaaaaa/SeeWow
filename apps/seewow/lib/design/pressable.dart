import 'package:flutter/material.dart';

import 'tokens.dart';

/// One press feedback for every clickable surface: 0.965 scale + slight dim.
///
/// 除了鼠标手感，它还负责三件容易漏的事：键盘可聚焦并用 Enter / Space 激活、
/// 禁用态不再显示手型光标、系统开启「减弱动态效果」时把动画时长归零。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.965,
    this.onHoverChanged,
    this.focusRadius = 12,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final ValueChanged<bool>? onHoverChanged;

  /// 焦点环的圆角，跟卡片自身的圆角对齐。
  final double focusRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Duration ms(int value) =>
        reduce ? Duration.zero : Duration(milliseconds: value);
    final active = _down && enabled
        ? widget.scale
        : (_hover && enabled ? 1.012 : 1.0);
    return Semantics(
      button: true,
      enabled: enabled,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) {
          setState(() => _hover = value);
          widget.onHoverChanged?.call(value);
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: enabled ? (_) => setState(() => _down = true) : null,
              onTapCancel: enabled ? () => setState(() => _down = false) : null,
              onTapUp: enabled ? (_) => setState(() => _down = false) : null,
              onTap: widget.onTap,
              child: AnimatedScale(
                scale: active,
                duration: ms(180),
                curve: WowMotion.snappy,
                child: AnimatedOpacity(
                  opacity: _down ? 0.86 : 1,
                  duration: ms(120),
                  child: widget.child,
                ),
              ),
            ),
            // 焦点环画在负偏移上，不参与布局，不会让卡片跳动。
            if (_focused)
              Positioned(
                left: -3,
                top: -3,
                right: -3,
                bottom: -3,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: WowColors.accent.withValues(alpha: 0.9),
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(widget.focusRadius),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Editorial section rule: numeral — title — hairline — label.
/// The numeral and the label carry the metadata; the title carries the voice.
class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.index,
    required this.title,
    this.subtitle,
    this.trailing,
  });
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
            style: WowType.display(
              30,
              FontWeight.w500,
              spacing: -0.6,
              height: 0.9,
              color: Colors.white.withValues(alpha: 0.26),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: WowType.display(
            27,
            FontWeight.w400,
            spacing: -0.6,
            height: 1.0,
          ),
        ),
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
            // 9px 的弱色标签在大屏上几乎读不到；抬到 10px 并改用 body 弱色。
            child: Text(
              subtitle!.toUpperCase(),
              style: WowType.monoLabel(
                10,
                color: WowColors.muted,
                spacing: 1.6,
              ),
            ),
          ),
        ],
        if (trailing != null) ...[const SizedBox(width: 18), trailing!],
      ],
    );
  }
}
