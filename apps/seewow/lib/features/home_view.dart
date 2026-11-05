import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/library_store.dart';
import '../design/artwork.dart';
import '../design/entrance.dart';
import '../design/gate.dart';
import '../design/poster_tile.dart';
import '../design/pressable.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key, required this.store, required this.onOpen, required this.onPlay});
  final LibraryStore store;
  final void Function(MediaItem item) onOpen;
  final void Function(MediaItem item) onPlay;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  static const _dwell = Duration(seconds: 9);

  int _hero = 0;
  bool _hoverHero = false;
  Timer? _timer;

  List<MediaItem> get _featured {
    final list = [...widget.store.continueWatching, ...widget.store.movies];
    final seen = <String>{};
    return list.where((i) => seen.add(i.id)).take(5).toList();
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_dwell, (_) {
      if (!mounted || _hoverHero) return;
      final list = _featured;
      if (list.length < 2) return;
      setState(() => _hero = (_hero + 1) % list.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final featured = _featured;
    final index = featured.isEmpty ? 0 : _hero % featured.length;
    final item = featured.isEmpty ? null : featured[index];
    final width = MediaQuery.sizeOf(context).width;
    final gutter = WowSpace.gutter(width);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 72),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item != null)
            _Hero(
              key: ValueKey('hero-${item.id}'),
              item: item,
              index: index,
              total: featured.length,
              gutter: gutter,
              hover: _hoverHero,
              onHover: (v) => setState(() => _hoverHero = v),
              onPlay: () => widget.onPlay(item),
              onOpen: () => widget.onOpen(item),
              onSelect: (i) => setState(() => _hero = i),
            )
          else
            _EmptyHero(gutter: gutter),
          const SizedBox(height: 52),
          if (widget.store.continueWatching.isNotEmpty) ...[
            RiseIn(
              delay: const Duration(milliseconds: 60),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: SectionHeading(index: 1, title: '继续观看', subtitle: 'PICK UP WHERE YOU LEFT OFF'),
              ),
            ),
            const SizedBox(height: 22),
            _LandscapeRail(items: widget.store.continueWatching, gutter: gutter, onOpen: widget.onOpen),
            const SizedBox(height: 56),
          ],
          if (widget.store.movies.isNotEmpty) ...[
            RiseIn(
              delay: const Duration(milliseconds: 120),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: SectionHeading(index: 2, title: '电影', subtitle: '${widget.store.movies.length} FILMS'),
              ),
            ),
            const SizedBox(height: 22),
            _PosterRail(items: widget.store.movies, gutter: gutter, onOpen: widget.onOpen),
            const SizedBox(height: 56),
          ],
          if (widget.store.series.isNotEmpty) ...[
            RiseIn(
              delay: const Duration(milliseconds: 180),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: SectionHeading(index: 3, title: '剧集', subtitle: '${widget.store.series.length} SERIES'),
              ),
            ),
            const SizedBox(height: 22),
            _PosterRail(items: widget.store.series, gutter: gutter, onOpen: widget.onOpen),
            const SizedBox(height: 40),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    super.key,
    required this.item,
    required this.index,
    required this.total,
    required this.gutter,
    required this.hover,
    required this.onHover,
    required this.onPlay,
    required this.onOpen,
    required this.onSelect,
  });

  final MediaItem item;
  final int index;
  final int total;
  final double gutter;
  final bool hover;
  final ValueChanged<bool> onHover;
  final VoidCallback onPlay;
  final VoidCallback onOpen;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final height = (size.height * 0.62).clamp(432.0, 604.0);
    final wide = size.width >= 1180;
    final showPlate = size.width >= 1120;
    final compact = size.width < 860;
    final titleSize = size.width >= 1180 ? 68.0 : (size.width >= 900 ? 56.0 : 44.0);

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Backdrop(item: item),
            // Left-to-right scrim: text sits in ink, artwork keeps breathing room on the right.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Color(0xF2000000), Color(0xCC000000), Color(0x59000000), Color(0x00000000)],
                  stops: [0, 0.34, 0.64, 1],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x66000000), Color(0xE6000000)],
                  stops: [0, 0.62, 1],
                ),
              ),
            ),
            if (hover)
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.75, 0.1),
                      radius: 0.95,
                      colors: [WowColors.accent.withValues(alpha: 0.10), Colors.transparent],
                    ),
                  ),
                ),
              ),
            // Projection gate: hairline frame with cut corners.
            Positioned.fill(child: GateFrame(inset: compact ? 14 : 22, opacity: 0.12)),
            if (showPlate)
              Positioned(
                right: gutter * 0.86,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _HeroPlate(item: item, index: index, total: total, heroHeight: height, hover: hover),
                ),
              ),
            Positioned(
              left: compact ? 26 : gutter,
              right: compact ? 26 : gutter,
              bottom: compact ? 28 : 44,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  RiseIn(
                    delay: const Duration(milliseconds: 40),
                    child: Row(
                      children: [
                        Text(
                          item.progress > 0 ? '继续观看' : '为你推荐',
                          style: WowType.monoLabel(9.5, weight: FontWeight.w600, color: WowColors.accent, spacing: 3.0),
                        ),
                        const SizedBox(width: 14),
                        Container(width: 26, height: 1, color: WowColors.accent.withValues(alpha: 0.45)),
                        const SizedBox(width: 14),
                        Text('FEATURED ${(index + 1).toString().padLeft(2, '0')} / ${total.toString().padLeft(2, '0')}',
                            style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.42), spacing: 2.2)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  RiseIn(
                    delay: const Duration(milliseconds: 90),
                    child: Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: WowType.display(titleSize, FontWeight.w500, spacing: -titleSize * 0.026, height: 0.98),
                    ),
                  ),
                  const SizedBox(height: 16),
                  RiseIn(delay: const Duration(milliseconds: 150), child: _MetaLine(item: item)),
                  const SizedBox(height: 16),
                  RiseIn(
                    delay: const Duration(milliseconds: 200),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 540),
                      child: Text(
                        item.overview.isNotEmpty ? item.overview : '本地片库 · ${item.container}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WowType.body(13.5, color: Colors.white.withValues(alpha: 0.66), height: 1.75),
                      ),
                    ),
                  ),
                  if (item.progress > 0.01) ...[
                    const SizedBox(height: 22),
                    RiseIn(delay: const Duration(milliseconds: 240), child: _Progress(item: item)),
                  ],
                  const SizedBox(height: 26),
                  RiseIn(
                    delay: const Duration(milliseconds: 290),
                    child: Row(
                      children: [
                        Magnetic(
                          child: _PrimaryButton(label: item.progress > 0 ? '继续播放' : '播放', onTap: onPlay),
                        ),
                        const SizedBox(width: 12),
                        _GhostButton(label: '详情', icon: Icons.info_outline_rounded, onTap: onOpen),
                        const Spacer(),
                        for (var i = 0; i < total; i++)
                          Pressable(
                            onTap: () => onSelect(i),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    (i + 1).toString().padLeft(2, '0'),
                                    style: WowType.monoLabel(
                                      10,
                                      weight: i == index ? FontWeight.w700 : FontWeight.w400,
                                      color: i == index ? Colors.white : Colors.white.withValues(alpha: 0.28),
                                      spacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  AnimatedContainer(
                                    duration: WowMotion.pageDuration,
                                    curve: WowMotion.page,
                                    width: i == index ? 30 : 10,
                                    height: 1,
                                    color: i == index ? WowColors.accent : Colors.white.withValues(alpha: 0.14),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Dwell cue: an inset hairline that draws itself across the gate for one hero cycle.
            Positioned(
              left: compact ? 26 : gutter,
              right: compact ? 26 : gutter,
              bottom: compact ? 14 : 20,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Container(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                          TweenAnimationBuilder<double>(
                            key: ValueKey('dwell-$index-$total'),
                            tween: Tween<double>(begin: 0, end: 1),
                            duration: _HomeViewState._dwell,
                            curve: Curves.easeInOut,
                            builder: (context, value, _) => Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: value.clamp(0.0, 1.0),
                                child: Container(height: 1, color: WowColors.accent.withValues(alpha: 0.7)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('AUTO', style: WowType.monoLabel(7.5, color: Colors.white.withValues(alpha: 0.28), spacing: 2.4)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPlate extends StatelessWidget {
  const _HeroPlate({
    required this.item,
    required this.index,
    required this.total,
    required this.heroHeight,
    required this.hover,
  });

  final MediaItem item;
  final int index;
  final int total;
  final double heroHeight;
  final bool hover;

  @override
  Widget build(BuildContext context) {
    final h = math.min(heroHeight * 0.66, 372.0);
    final w = h * 2 / 3;
    final poster = item.posterUrl;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topRight,
          children: [
            // Ghost numeral: the reel number, printed behind the frame.
            Positioned(
              right: -4,
              top: 0,
              child: IgnorePointer(
                child: Text(
                  (index + 1).toString().padLeft(2, '0'),
                  style: WowType.display(h * 0.36, FontWeight.w500, spacing: -h * 0.02, height: 0.86)
                      .copyWith(color: Colors.white.withValues(alpha: 0.07)),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 420),
              curve: WowMotion.page,
              transform: Matrix4.translationValues(0, hover ? -7 : 0, 0),
              child: Container(
                width: w,
                height: h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 60, offset: const Offset(0, 26)),
                    BoxShadow(color: WowColors.accent.withValues(alpha: 0.10), blurRadius: 40, spreadRadius: -6),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (poster != null && poster.isNotEmpty)
                        WowArt(url: poster, headers: item.httpHeaders, fallback: const _BackdropFallback())
                      else
                        const _BackdropFallback(),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x00000000), Color(0x00000000), Color(0x99000000)],
                            stops: [0, 0.62, 1],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        top: 12,
                        child: Text('SEEWOW', style: WowType.monoLabel(7, color: Colors.white.withValues(alpha: 0.55), spacing: 2.4)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 22, height: 1, color: WowColors.accent.withValues(alpha: 0.4)),
            const SizedBox(width: 9),
            Text(
              'NOW SHOWING',
              style: WowType.monoLabel(8, color: Colors.white.withValues(alpha: 0.42), spacing: 2.4),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    void dot() {
      if (parts.isEmpty) return;
      parts.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(width: 1, height: 10, color: Colors.white.withValues(alpha: 0.18)),
      ));
    }

    if (item.year != null) {
      parts.add(Text('${item.year}', style: WowType.monoLabel(10.5, color: Colors.white.withValues(alpha: 0.72), spacing: 1.2)));
    }
    if (item.rating != null) {
      dot();
      parts.add(Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFFC861)),
        const SizedBox(width: 4),
        Text(item.rating!.toStringAsFixed(1), style: WowType.monoLabel(10.5, color: Colors.white.withValues(alpha: 0.92), spacing: 0.4)),
      ]));
    }
    if (item.badgeText.isNotEmpty) {
      dot();
      parts.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(item.badgeText.toUpperCase(), style: WowType.monoLabel(8, weight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.9), spacing: 1.2)),
        ),
      );
    }
    if (item.genres.isNotEmpty) {
      dot();
      parts.add(Text(item.genres.take(3).join('  /  '), style: WowType.monoLabel(9.5, color: Colors.white.withValues(alpha: 0.52), spacing: 1.2)));
    }
    if (item.duration > 0) {
      dot();
      parts.add(Text(_runtimeLabel(item.duration), style: WowType.monoLabel(9.5, color: Colors.white.withValues(alpha: 0.52), spacing: 1.2)));
    }
    return Row(children: parts);
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final pct = (item.progress * 100).round();
    final left = (item.remainingSeconds / 60).ceil();
    final leftLabel = left < 60 ? '$left 分钟' : '${left ~/ 60} 小时 ${left % 60} 分';
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(1),
            child: SizedBox(
              height: 2,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: 0.16))),
                  FractionallySizedBox(widthFactor: item.progress.clamp(0.0, 1.0), child: const ColoredBox(color: WowColors.accent)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text('$pct% WATCHED', style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.56), spacing: 1.6)),
              const Spacer(),
              Text('$leftLabel LEFT', style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.38), spacing: 1.6)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final path = item.backdropUrl ?? item.posterUrl;
    final tint = _tintFor(item.title);
    final art = (path != null && path.isNotEmpty)
        ? ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              1.14, 0, 0, 0, 8,
              0, 1.12, 0, 0, 7,
              0, 0, 1.10, 0, 6,
              0, 0, 0, 1, 0,
            ]),
            child: WowArt(url: path, headers: item.httpHeaders, fallback: const _BackdropFallback()),
          )
        : const _BackdropFallback();

    return Stack(
      fit: StackFit.expand,
      children: [
        // Slow push-in: the still is always alive, never a frozen banner.
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 1.0, end: 1.06),
          duration: const Duration(seconds: 14),
          curve: Curves.easeOutCubic,
          builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          child: art,
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.8, 0.0),
                radius: 1.0,
                colors: [tint.withValues(alpha: 0.22), Colors.transparent],
              ),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x00000000), Color(0x2E000000), Color(0x99000000)],
              stops: [0, 0.5, 1],
            ),
          ),
        ),
      ],
    );
  }
}

Color _tintFor(String title) {
  final h = title.codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0x7fffffff);
  final hue = 18 + (h % 300);
  return HSLColor.fromAHSL(1, hue.toDouble(), 0.52, 0.52).toColor();
}

class _BackdropFallback extends StatelessWidget {
  const _BackdropFallback();
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0.2, -0.1),
          radius: 1.1,
          colors: [Color(0xFF40311C), Color(0xFF120F0A), Color(0xFF07080B)],
          stops: [0, 0.55, 1],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 13),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow_rounded, size: 20, color: Colors.black),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white.withValues(alpha: 0.82)),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

class _LandscapeRail extends StatefulWidget {
  const _LandscapeRail({required this.items, required this.gutter, required this.onOpen});
  final List<MediaItem> items;
  final double gutter;
  final void Function(MediaItem) onOpen;

  @override
  State<_LandscapeRail> createState() => _LandscapeRailState();
}

class _LandscapeRailState extends State<_LandscapeRail> {
  int _hovered = -1;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 196,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: widget.gutter),
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 20),
        itemBuilder: (_, i) => LandscapeTile(
          item: widget.items[i],
          width: 330,
          dimmed: _hovered >= 0 && _hovered != i,
          onHoverChanged: (v) => setState(() => _hovered = v ? i : (_hovered == i ? -1 : _hovered)),
          onTap: () => widget.onOpen(widget.items[i]),
        ),
      ),
    );
  }
}

class _PosterRail extends StatefulWidget {
  const _PosterRail({required this.items, required this.gutter, required this.onOpen});
  final List<MediaItem> items;
  final double gutter;
  final void Function(MediaItem) onOpen;

  @override
  State<_PosterRail> createState() => _PosterRailState();
}

class _PosterRailState extends State<_PosterRail> {
  int _hovered = -1;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 352,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: widget.gutter),
        itemCount: widget.items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 22),
        itemBuilder: (_, i) => PosterTile(
          item: widget.items[i],
          width: 190,
          dimmed: _hovered >= 0 && _hovered != i,
          onHoverChanged: (v) => setState(() => _hovered = v ? i : (_hovered == i ? -1 : _hovered)),
          onTap: () => widget.onOpen(widget.items[i]),
        ),
      ),
    );
  }
}

class _EmptyHero extends StatelessWidget {
  const _EmptyHero({required this.gutter});
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: gutter, right: gutter, top: 24),
      child: SizedBox(
        height: 520,
        child: Stack(
          children: [
            const Positioned.fill(child: GateFrame(inset: 18, opacity: 0.10)),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [WowColors.accent, WowColors.accent2]),
                    ),
                    child: const Icon(Icons.movie_filter_outlined, color: Colors.white, size: 32),
                  ),
                  const SizedBox(height: 26),
                  Text('把你的片库带进来', style: WowType.display(44, FontWeight.w400, spacing: -1.2)),
                  const SizedBox(height: 14),
                  Text(
                    '本地文件夹、NAS、WebDAV、Emby / Jellyfin / Plex，一个 App 全部搞定。',
                    style: WowType.body(13, color: WowColors.muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 26, height: 1, color: WowColors.line),
                      const SizedBox(width: 12),
                      Text('前往「设置」添加片源', style: WowType.monoLabel(9, color: WowColors.faint, spacing: 2.0)),
                      const SizedBox(width: 12),
                      Container(width: 26, height: 1, color: WowColors.line),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _runtimeLabel(double seconds) {
  final m = (seconds / 60).round();
  if (m < 60) return '$m 分钟';
  final h = m ~/ 60;
  final rest = m % 60;
  return rest == 0 ? '$h 小时' : '$h 小时 $rest 分';
}