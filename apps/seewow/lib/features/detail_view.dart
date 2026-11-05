import 'package:flutter/material.dart';
import '../data/library_store.dart';
import '../design/artwork.dart';
import '../design/gate.dart';
import '../design/poster_tile.dart';
import '../design/pressable.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';

class DetailView extends StatelessWidget {
  const DetailView({super.key, required this.item, required this.store, required this.onPlay});
  final MediaItem item;
  final LibraryStore store;
  final void Function(MediaItem item) onPlay;

  @override
  Widget build(BuildContext context) {
    final episodes = store.episodes.where((e) => (e.showTitle ?? e.title) == (item.showTitle ?? item.title)).toList()
      ..sort((a, b) => ((a.season ?? 0) * 1000 + (a.episode ?? 0)).compareTo((b.season ?? 0) * 1000 + (b.episode ?? 0)));
    final related = store.movies.where((m) => m.id != item.id).take(12).toList();
    final gutter = WowSpace.gutter(MediaQuery.sizeOf(context).width);
    var section = 1;

    return Scaffold(
      backgroundColor: WowColors.ink,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(item: item, onPlay: () => onPlay(item), gutter: gutter),
            Padding(
              padding: EdgeInsets.fromLTRB(gutter, 38, gutter, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (episodes.isNotEmpty) ...[
                    SectionHeading(index: section++, title: '剧集', subtitle: 'EPISODES', trailing: _count(episodes.length, '集')),
                    const SizedBox(height: 18),
                    for (var i = 0; i < episodes.length; i++)
                      _EpisodeRow(item: episodes[i], index: i, onPlay: () => onPlay(episodes[i])),
                    const SizedBox(height: 46),
                  ],
                  SectionHeading(index: section++, title: '简介', subtitle: 'SYNOPSIS'),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Text(
                      item.overview.isNotEmpty ? item.overview : '这个条目还没有简介。填入 TMDB API Key 后可自动抓取中文简介与高清海报；本地 poster.jpg / fanart.jpg 会优先使用。',
                      style: WowType.body(13.5, color: Colors.white.withValues(alpha: 0.66), height: 1.9),
                    ),
                  ),
                  const SizedBox(height: 46),
                  SectionHeading(index: section++, title: '文件信息', subtitle: 'FILE'),
                  const SizedBox(height: 18),
                  Wrap(spacing: 64, runSpacing: 18, children: [
                    _Info(label: '来源', value: store.sources.firstWhere((s) => s.id == item.sourceId, orElse: () => store.sources.first).name),
                    _Info(label: '格式', value: item.container.isEmpty ? '—' : item.container),
                    _Info(label: '大小', value: item.fileSize <= 0 ? '—' : '${(item.fileSize / 1024 / 1024).toStringAsFixed(0)} MB'),
                    _Info(label: '路径', value: item.locator.split('/').last),
                  ]),
                  if (related.isNotEmpty) ...[
                    const SizedBox(height: 52),
                    SectionHeading(index: section++, title: '更多影片', subtitle: 'MORE LIKE THIS'),
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 300,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: related.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 20),
                        itemBuilder: (_, i) => PosterTile(
                          item: related[i],
                          width: 160,
                          onTap: () => Navigator.of(context).pushReplacement(
                            MaterialPageRoute(builder: (_) => DetailView(item: related[i], store: store, onPlay: onPlay)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _count(int n, String unit) =>
      Text('$n $unit', style: WowType.monoLabel(9, color: WowColors.faint, spacing: 1.6));
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.onPlay, required this.gutter});
  final MediaItem item;
  final VoidCallback onPlay;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 860;
    final backdrop = item.backdropUrl ?? item.posterUrl;
    return SizedBox(
      height: compact ? 420 : 460,
      child: Stack(
        fit: StackFit.expand,
        children: [
          WowArt(
            url: backdrop,
            headers: item.httpHeaders,
            fallback: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(center: Alignment(0.4, -0.2), radius: 1.2, colors: [Color(0xFF3B2C1C), Color(0xFF0B0A0C), WowColors.ink]),
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [Color(0xF2000000), Color(0xCC000000), Color(0x55000000), Color(0xCC000000)], stops: [0, 0.45, 0.75, 1]),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x22000000), Colors.transparent, Color(0xE6000000)], stops: [0, 0.55, 1]),
            ),
          ),
          const Positioned.fill(child: GateFrame(inset: 18, opacity: 0.10)),
          // Editorial watermark: the release year, engraved into the artwork.
          if (!compact && item.year != null)
            Positioned(
              right: gutter * 0.55,
              top: 26,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('RELEASE', style: WowType.monoLabel(7.5, color: Colors.white.withValues(alpha: 0.22), spacing: 3.0)),
                    Text(
                      '${item.year}',
                      style: WowType.display(88, FontWeight.w400, spacing: -2.4, height: 0.86, color: Colors.white.withValues(alpha: 0.03)),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: gutter,
            top: 16,
            child: Pressable(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.arrow_back_rounded, size: 13, color: Colors.white.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Text('返回', style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.78), spacing: 1.8)),
                ]),
              ),
            ),
          ),
          Positioned(
            left: compact ? 24 : gutter,
            right: gutter,
            bottom: 40,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!compact)
                  Container(
                    width: 196,
                    height: 294,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 50, offset: const Offset(0, 22)),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(fit: StackFit.expand, children: [
                        WowArt(url: item.posterUrl, headers: item.httpHeaders, fallback: Container(color: WowColors.panel)),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0x66000000)], stops: [0.6, 1]),
                          ),
                        ),
                      ]),
                    ),
                  ),
                if (!compact) const SizedBox(width: 38),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Container(width: 18, height: 1, color: WowColors.accent.withValues(alpha: 0.6)),
                        const SizedBox(width: 9),
                        Text(item.kind == MediaKind.episode ? '剧集 · SERIES' : '电影 · FILM',
                            style: WowType.monoLabel(8.5, weight: FontWeight.w600, color: WowColors.accent, spacing: 2.6)),
                      ]),
                      const SizedBox(height: 14),
                      Text(
                        item.kind == MediaKind.episode ? (item.showTitle ?? item.title) : item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: WowType.display(compact ? 38 : 52, FontWeight.w500, spacing: -1.4, height: 1.0),
                      ),
                      if (item.kind == MediaKind.episode) ...[
                        const SizedBox(height: 10),
                        Text('第 ${item.season ?? 1} 季 · 第 ${item.episode ?? 1} 集',
                            style: WowType.monoLabel(10, color: Colors.white.withValues(alpha: 0.55), spacing: 1.4)),
                      ],
                      const SizedBox(height: 16),
                      _MetaLine(item: item),
                      const SizedBox(height: 24),
                      Row(children: [
                        Pressable(
                          onTap: onPlay,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.play_arrow_rounded, size: 19, color: Colors.black),
                              const SizedBox(width: 6),
                              Text(item.progress > 0 ? '继续播放' : '播放',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _circle(Icons.favorite_border_rounded),
                        const SizedBox(width: 8),
                        _circle(Icons.downloading_rounded),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(IconData icon) => Pressable(
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06), border: Border.all(color: Colors.white.withValues(alpha: 0.14))),
          child: Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.75)),
        ),
      );
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final parts = <Widget>[];
    void dot() {
      if (parts.isEmpty) return;
      parts.add(Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Container(width: 1, height: 10, color: Colors.white.withValues(alpha: 0.18))));
    }

    if (item.year != null) {
      parts.add(Text('${item.year}', style: WowType.monoLabel(10.5, color: Colors.white.withValues(alpha: 0.7), spacing: 1.2)));
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
      parts.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(border: Border.all(color: Colors.white.withValues(alpha: 0.28)), borderRadius: BorderRadius.circular(3)),
        child: Text(item.badgeText.toUpperCase(), style: WowType.monoLabel(8, weight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.9), spacing: 1.2)),
      ));
    }
    if (item.genres.isNotEmpty) {
      dot();
      parts.add(Text(item.genres.take(3).join('  /  '), style: WowType.monoLabel(9.5, color: Colors.white.withValues(alpha: 0.52), spacing: 1.2)));
    }
    if (item.duration > 0) {
      dot();
      parts.add(Text(_minutes(item.duration), style: WowType.monoLabel(9.5, color: Colors.white.withValues(alpha: 0.52), spacing: 1.2)));
    }
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: parts);
  }

  String _minutes(double seconds) {
    final m = (seconds / 60).round();
    return m >= 60 ? '${m ~/ 60} 小时 ${m % 60} 分' : '$m 分钟';
  }
}

class _EpisodeRow extends StatefulWidget {
  const _EpisodeRow({required this.item, required this.index, required this.onPlay});
  final MediaItem item;
  final int index;
  final VoidCallback onPlay;
  @override
  State<_EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<_EpisodeRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onTap: widget.onPlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: _hover ? Colors.white.withValues(alpha: 0.055) : Colors.white.withValues(alpha: 0.018),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: _hover ? Colors.white.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.045)),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(6), color: Colors.white.withValues(alpha: 0.04), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
              child: Text('${(widget.item.episode ?? widget.index + 1)}'.padLeft(2, '0'),
                  style: WowType.monoLabel(10, color: Colors.white.withValues(alpha: 0.7), spacing: 0.5)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.item.kind == MediaKind.episode ? '第 ${widget.item.episode ?? widget.index + 1} 集' : widget.item.title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                const SizedBox(height: 3),
                Text(
                  [widget.item.badgeText, if (widget.item.duration > 0) '${(widget.item.duration / 60).round()} 分钟'].where((s) => s.isNotEmpty).join('  ·  '),
                  style: WowType.monoLabel(8, color: WowColors.faint, spacing: 1),
                ),
              ]),
            ),
            if (widget.item.progress > 0.01)
              Text('${(widget.item.progress * 100).round()}%', style: WowType.monoLabel(8.5, color: WowColors.accent, spacing: 0.8)),
            const SizedBox(width: 12),
            Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white.withValues(alpha: _hover ? 0.9 : 0.32)),
          ]),
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: WowType.monoLabel(8, color: WowColors.faint, spacing: 1.6)),
      const SizedBox(height: 6),
      Text(value, style: WowType.monoLabel(10.5, color: Colors.white.withValues(alpha: 0.8), spacing: 0.2)),
    ]);
  }
}