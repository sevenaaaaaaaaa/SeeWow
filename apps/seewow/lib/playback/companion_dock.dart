import 'package:flutter/material.dart';

/// 播放器里的浮窗：陪看面板漂在画面上，片子照放。
///
/// 它只负责「漂在哪、有多大、收起来长什么样」；内容由外面传进来，
/// 会话也归外面管——收起只是收窗口，不打断正在生成的回答。
class CompanionDock extends StatefulWidget {
  const CompanionDock({
    super.key,
    required this.panel,
    required this.collapsed,
    required this.onCollapse,
    required this.onExpand,
    this.width = 340,
    this.panelHeight = 340,
    this.busy = false,
  });

  final Widget panel;
  final bool collapsed;
  final VoidCallback onCollapse, onExpand;
  final double width, panelHeight;

  /// 有回答正在生成时，气泡上点一个状态点，收起也不丢进度感。
  final bool busy;

  static const double gripHeight = 18;
  static const double bubbleSize = 56;

  @override
  State<CompanionDock> createState() => _CompanionDockState();
}

class _CompanionDockState extends State<CompanionDock> {
  Offset? _offset;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final safe = MediaQuery.paddingOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final size = widget.collapsed
        ? const Size(CompanionDock.bubbleSize, CompanionDock.bubbleSize)
        : Size(
            widget.width.clamp(240.0, screen.width - 24),
            widget.panelHeight + CompanionDock.gripHeight,
          );
    final fallback = Offset(
      screen.width - size.width - 12,
      screen.height - size.height - 96 - keyboard,
    );
    final wanted = _offset ?? fallback;
    // 拖到哪都行，但别拖出画面，也别钻到键盘底下。
    final position = Offset(
      wanted.dx.clamp(
        8.0,
        (screen.width - size.width - 8).clamp(8.0, screen.width),
      ),
      wanted.dy.clamp(
        safe.top + 8,
        (screen.height - size.height - 8 - keyboard).clamp(
          safe.top + 8,
          screen.height,
        ),
      ),
    );

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: widget.collapsed ? _bubble() : _card(size),
    );
  }

  void _drag(DragUpdateDetails details) {
    final current = _offset ?? Offset.zero;
    // 第一次拖之前先落到默认位置，否则会从 (0,0) 起跳。
    if (_offset == null) {
      final screen = MediaQuery.sizeOf(context);
      final keyboard = MediaQuery.viewInsetsOf(context).bottom;
      final size = widget.collapsed
          ? const Size(CompanionDock.bubbleSize, CompanionDock.bubbleSize)
          : Size(
              widget.width.clamp(240.0, screen.width - 24),
              widget.panelHeight + CompanionDock.gripHeight,
            );
      _offset = Offset(
        screen.width - size.width - 12,
        screen.height - size.height - 96 - keyboard,
      );
    }
    setState(() => _offset = (_offset ?? current) + details.delta);
  }

  Widget _bubble() => Semantics(
    button: true,
    label: '展开小映',
    child: GestureDetector(
      onTap: widget.onExpand,
      onPanUpdate: _drag,
      child: Tooltip(
        message: '小映（点击展开）',
        child: SizedBox(
          key: const ValueKey('companionBubble'),
          width: CompanionDock.bubbleSize,
          height: CompanionDock.bubbleSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: .72),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .22),
                  ),
                ),
                child: const Icon(
                  Icons.face_3_outlined,
                  size: 28,
                  color: Color(0xFFFFE3AD),
                ),
              ),
              if (widget.busy)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF7BD1C8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _card(Size size) => SizedBox(
    key: const ValueKey('companionCard'),
    width: size.width,
    height: size.height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF141416).withValues(alpha: .94),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 26, spreadRadius: 2),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: _drag,
            child: SizedBox(
              key: const ValueKey('companionGrip'),
              height: CompanionDock.gripHeight,
              child: Center(
                child: Container(
                  width: 36,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .28),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: widget.panelHeight,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
              child: widget.panel,
            ),
          ),
        ],
      ),
    ),
  );
}
