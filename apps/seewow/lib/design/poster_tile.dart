import 'package:flutter/material.dart';

import '../domain/media_item.dart';
import 'artwork.dart';
import 'pressable.dart';
import 'skin.dart';
import 'tokens.dart';

class PosterTile extends StatefulWidget {
  const PosterTile({
    super.key,
    required this.item,
    this.width = 190,
    this.onTap,
    this.showMeta = true,
    this.dimmed = false,
    this.onHoverChanged,
  });
  final MediaItem item;
  final double width;
  final VoidCallback? onTap;
  final bool showMeta;
  final bool dimmed;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<PosterTile> {
  Offset? _pointer;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final height = widget.width * 1.5;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    Duration ms(int value) =>
        reduce ? Duration.zero : Duration(milliseconds: value);
    // 有真海报时下面的标题才必要；占位海报自己会写标题，再重复一遍只是噪音。
    final hasArtwork = (widget.item.posterUrl ?? '').isNotEmpty;
    final glow = _pointer == null
        ? Alignment.topLeft
        : Alignment(_pointer!.dx * 2 - 1, _pointer!.dy * 2 - 1);
    return MouseRegion(
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final local = box.globalToLocal(e.position);
        if (!_hover) widget.onHoverChanged?.call(true);
        setState(() {
          _hover = true;
          _pointer = local;
        });
      },
      onExit: (_) {
        if (_hover) widget.onHoverChanged?.call(false);
        setState(() {
          _hover = false;
          _pointer = null;
        });
      },
      child: AnimatedOpacity(
        opacity: widget.dimmed && !_hover ? 0.46 : 1,
        duration: ms(240),
        curve: WowMotion.page,
        // 3D 倾斜已移除：网格里几十张卡片同时做透视旋转，既抢注意力也吃帧。
        child: Pressable(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: ms(300),
            curve: WowMotion.page,
            width: widget.width,
            transform: Matrix4.translationValues(0, _hover ? -6 : 0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    WowSkin.I.spec.posterRadius,
                  ),
                  child: SizedBox(
                    width: widget.width,
                    height: height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedScale(
                          scale: _hover ? 1.02 : 1,
                          duration: ms(420),
                          curve: WowMotion.page,
                          child: _PosterArt(item: widget.item),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x00000000),
                                Color(0x22000000),
                                Color(0xCC000000),
                              ],
                              stops: [0.45, 0.72, 1],
                            ),
                          ),
                        ),
                        // Cursor light: the poster catches the pointer like a print under a lamp.
                        AnimatedOpacity(
                          opacity: _hover ? 1 : 0,
                          duration: ms(220),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: glow,
                                radius: 0.85,
                                colors: [
                                  Colors.white.withValues(alpha: 0.14),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: WowMotion.page,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: _hover ? 0.34 : 0.07,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 12,
                          right: 12,
                          bottom: 11,
                          child: AnimatedOpacity(
                            opacity: _hover ? 1 : 0,
                            duration: const Duration(milliseconds: 220),
                            child: Row(
                              children: [
                                Text(
                                  widget.item.badgeText.toUpperCase(),
                                  style: WowType.monoLabel(
                                    8,
                                    color: Colors.white.withValues(alpha: 0.72),
                                    spacing: 1.4,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    size: 16,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.item.progress > 0.01)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: widget.item.progress,
                              minHeight: 2,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.14,
                              ),
                              valueColor: AlwaysStoppedAnimation(
                                WowColors.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (widget.showMeta) ...[
                  const SizedBox(height: 13),
                  // 占位海报已经把标题写在画面里，再重复一行只会让信息变吵。
                  if (hasArtwork)
                    Text(
                      widget.item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WowType.display(
                        15,
                        FontWeight.w600,
                        spacing: -0.1,
                        color: _hover
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                  if (hasArtwork) const SizedBox(height: 5),
                  Text(
                    [
                      if (widget.item.year != null) '${widget.item.year}',
                      if (widget.item.badgeText.isNotEmpty)
                        widget.item.badgeText,
                    ].join('   /   ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // 8px + 最弱色在大屏上读不出来；抬到 10px 并换用 muted。
                    style: WowType.monoLabel(
                      10,
                      color: WowColors.muted,
                      spacing: 1.2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterArt extends StatelessWidget {
  const _PosterArt({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final fallback = _AtmospherePoster(
      seed: item.title,
      hue: _hueFor(item.title),
    );
    return WowArt(
      url: item.posterUrl,
      headers: item.artworkHeaders(item.posterUrl),
      fallback: fallback,
    );
  }
}

double _hueFor(String title) {
  final h = title.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  return (h % 360).toDouble();
}

class _AtmospherePoster extends StatelessWidget {
  const _AtmospherePoster({required this.seed, required this.hue});
  final String seed;
  final double hue;

  @override
  Widget build(BuildContext context) {
    final neutral = WowSkin.I.posterId == WowPosterId.neutral;
    final c1 = neutral
        ? WowColors.panel
        : HSVColor.fromAHSV(1, hue, 0.32, 0.18).toColor();
    final c2 = neutral
        ? WowColors.panel
        : HSVColor.fromAHSV(1, (hue + 26) % 360, 0.42, 0.55).toColor();
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(color: c1)),
        Positioned(
          left: -40,
          top: 20,
          right: -40,
          bottom: 60,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                colors: [
                  c2.withValues(alpha: neutral ? 0 : 0.85),
                  c2.withValues(alpha: 0),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Text(
              seed.toUpperCase(),
              maxLines: 2,
              style: WowType.display(
                22,
                FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.92),
                spacing: 0,
              ),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Color(0xCC000000)],
              stops: [0.45, 1],
            ),
          ),
        ),
      ],
    );
  }
}

class LandscapeTile extends StatefulWidget {
  const LandscapeTile({
    super.key,
    required this.item,
    this.width = 320,
    this.onTap,
    this.dimmed = false,
    this.onHoverChanged,
  });
  final MediaItem item;
  final double width;
  final VoidCallback? onTap;
  final bool dimmed;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<LandscapeTile> createState() => _LandscapeTileState();
}

class _LandscapeTileState extends State<LandscapeTile> {
  Offset? _pointer;
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final glow = _pointer == null
        ? Alignment.topLeft
        : Alignment(_pointer!.dx * 2 - 1, _pointer!.dy * 2 - 1);
    return MouseRegion(
      onHover: (e) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        if (!_hover) widget.onHoverChanged?.call(true);
        setState(() {
          _hover = true;
          _pointer = box.globalToLocal(e.position);
        });
      },
      onExit: (_) {
        if (_hover) widget.onHoverChanged?.call(false);
        setState(() {
          _hover = false;
          _pointer = null;
        });
      },
      child: AnimatedOpacity(
        opacity: widget.dimmed && !_hover ? 0.5 : 1,
        duration: const Duration(milliseconds: 240),
        child: Pressable(
          onTap: widget.onTap,
          child: SizedBox(
            width: widget.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox(
                    width: widget.width,
                    height: widget.width * 0.5625,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        AnimatedScale(
                          scale: _hover ? 1.03 : 1,
                          duration: const Duration(milliseconds: 520),
                          curve: WowMotion.page,
                          child: _PosterArt(item: widget.item),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.88),
                              ],
                              stops: const [0.3, 1],
                            ),
                          ),
                        ),
                        AnimatedOpacity(
                          opacity: _hover ? 1 : 0,
                          duration: const Duration(milliseconds: 260),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: glow,
                                radius: 0.9,
                                colors: [
                                  Colors.white.withValues(alpha: 0.12),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: Colors.white.withValues(
                                alpha: _hover ? 0.3 : 0.06,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.item.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: WowType.display(
                                  17,
                                  FontWeight.w600,
                                  spacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                [
                                      if (widget.item.year != null)
                                        '${widget.item.year}',
                                      if (widget.item.badgeText.isNotEmpty)
                                        widget.item.badgeText,
                                      _remaining(widget.item),
                                    ]
                                    .where((s) => s.isNotEmpty)
                                    .join('   /   ')
                                    .toUpperCase(),
                                style: WowType.monoLabel(
                                  8,
                                  color: Colors.white.withValues(alpha: 0.55),
                                  spacing: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 12,
                          top: 12,
                          child: AnimatedOpacity(
                            opacity: _hover ? 1 : 0,
                            duration: const Duration(milliseconds: 220),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.92),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                size: 17,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                        if (widget.item.progress > 0.01)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: widget.item.progress,
                              minHeight: 2,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.14,
                              ),
                              valueColor: AlwaysStoppedAnimation(
                                WowColors.accent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _remaining(MediaItem item) {
    if (item.remainingSeconds <= 0) return '';
    final m = (item.remainingSeconds / 60).ceil();
    return '剩 $m 分';
  }
}
