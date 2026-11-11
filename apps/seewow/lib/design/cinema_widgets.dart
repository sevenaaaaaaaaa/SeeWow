import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../domain/media_item.dart';
import 'artwork.dart';
import 'tokens.dart';
import 'skin.dart';
import 'skin_surface.dart';

class CinemaPanel extends StatelessWidget {
  const CinemaPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => SkinSurface(
    color: color,
    child: Padding(padding: padding, child: child),
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontFamily: WowType.mono,
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 1.8,
      color: color ?? WowColors.muted,
    ),
  );
}

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    this.action,
  });
  final String eyebrow, title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(eyebrow),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1,
                ),
              ),
            ),
            if (action != null && box.maxWidth > 620) action!,
          ],
        ),
        const SizedBox(height: 8),
        Text(description, style: WowType.body(13, color: WowColors.muted)),
        if (action != null && box.maxWidth <= 620)
          Padding(padding: const EdgeInsets.only(top: 16), child: action!),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.4,
              ),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  subtitle!,
                  style: WowType.body(12, color: WowColors.muted),
                ),
              ),
          ],
        ),
      ),
      if (action != null) action!,
    ],
  );
}

class EmptyCinema extends StatelessWidget {
  const EmptyCinema({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: WowColors.muted),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Text(
              description,
              textAlign: TextAlign.center,
              style: WowType.body(13, color: WowColors.muted),
            ),
          ),
          if (action != null)
            Padding(padding: const EdgeInsets.only(top: 22), child: action!),
        ],
      ),
    ),
  );
}

class FilmArtwork extends StatelessWidget {
  const FilmArtwork({super.key, required this.item, this.landscape = false});
  final MediaItem item;
  final bool landscape;
  @override
  Widget build(BuildContext context) {
    final artwork = WowArt(
      url: landscape ? item.backdropUrl ?? item.posterUrl : item.posterUrl,
      headers: item.artworkHeaders(
        landscape ? item.backdropUrl ?? item.posterUrl : item.posterUrl,
      ),
      fallback: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(
                WowColors.ambient.withValues(alpha: .16),
                WowColors.panel,
              ),
              WowColors.panel,
              WowColors.shell,
            ],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            if (landscape || box.maxHeight < 130 || box.maxWidth < 80) {
              return Center(
                child: Icon(
                  item.kind == MediaKind.audio
                      ? Icons.album_outlined
                      : Icons.local_movies_outlined,
                  color: WowColors.muted,
                  size: box.maxWidth < 80 ? 20 : 36,
                ),
              );
            }
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: SizedBox(
                    width: 130,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.kind == MediaKind.audio
                              ? Icons.album_outlined
                              : Icons.local_movies_outlined,
                          color: WowColors.muted,
                          size: 30,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          item.libraryTitle,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${item.year ?? 'SEEWOW'}',
                          style: WowType.monoLabel(10),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    final shown = landscape
        ? item.backdropUrl ?? item.posterUrl
        : item.posterUrl;
    if (!item.hasGeneratedCover || shown != item.posterUrl) return artwork;
    return LayoutBuilder(
      builder: (context, box) {
        final compact = box.maxWidth < 90 || box.maxHeight < 90;
        return Stack(
          fit: StackFit.expand,
          children: [
            artwork,
            Positioned(
              right: compact ? 2 : 8,
              bottom: compact ? 2 : 8,
              child: Semantics(
                label: 'AI 生成的配图，非官方海报',
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 4 : 7,
                    vertical: compact ? 2 : 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .8),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    compact ? 'AI' : 'AI 配图',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 9 : 10,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class FilmCard extends StatefulWidget {
  const FilmCard({
    super.key,
    required this.item,
    required this.store,
    required this.onOpen,
    this.reason,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
  });
  final MediaItem item;
  final LibraryStore store;
  final VoidCallback onOpen;
  final String? reason;
  final bool selectionMode, selected;
  final VoidCallback? onSelect;
  @override
  State<FilmCard> createState() => _FilmCardState();
}

class _FilmCardState extends State<FilmCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final i = widget.store.current(widget.item);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Material(
                  color: WowColors.panel,
                  borderRadius: BorderRadius.circular(
                    WowSkin.I.spec.posterRadius,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.selectionMode
                        ? widget.onSelect
                        : widget.onOpen,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FilmArtwork(item: i),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: .14),
                                Colors.transparent,
                                Colors.black.withValues(alpha: .5),
                              ],
                            ),
                          ),
                        ),
                        if (_hover && !widget.selectionMode)
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: widget.selectionMode
                      ? Checkbox(
                          value: widget.selected,
                          onChanged: (_) => widget.onSelect?.call(),
                        )
                      : i.watched
                      ? const _Badge('已看', icon: Icons.check_rounded)
                      : i.badgeText.isNotEmpty
                      ? _Badge(i.badgeText)
                      : const SizedBox.shrink(),
                ),
                if (!widget.selectionMode)
                  Positioned(
                    right: 1,
                    top: 1,
                    child: PopupMenuButton<String>(
                      tooltip: '${i.title}的操作',
                      icon: const Icon(Icons.more_horiz, color: Colors.white),
                      onSelected: (v) {
                        switch (v) {
                          case 'watchlist':
                            widget.store.toggleWatchlist(i);
                          case 'favorite':
                            widget.store.setFavorite(i, !i.isFavorite);
                          case 'watched':
                            widget.store.markWatched([i], !i.watched);
                          case 'dislike':
                            widget.store.setDisliked(
                              i,
                              !widget.store.taste.dislikedIds.contains(i.id),
                            );
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'watchlist',
                          child: Text(
                            widget.store.taste.watchlist.contains(i.id)
                                ? '移出待看'
                                : '加入待看',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'favorite',
                          child: Text(i.isFavorite ? '取消喜欢' : '喜欢 · 更多类似推荐'),
                        ),
                        PopupMenuItem(
                          value: 'watched',
                          child: Text(i.watched ? '标记为未看' : '标记为已看'),
                        ),
                        PopupMenuItem(
                          value: 'dislike',
                          child: Text(
                            widget.store.taste.dislikedIds.contains(i.id)
                                ? '恢复推荐'
                                : '不感兴趣 · 减少推荐',
                          ),
                        ),
                      ],
                    ),
                  ),
                if (i.progress > 0 && !i.watched)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: i.progress,
                      minHeight: 3,
                      color: WowColors.accent,
                      backgroundColor: Colors.black45,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            i.libraryTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${i.year ?? '年份未知'}${i.genres.isEmpty ? '' : ' · ${i.genres.first}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: WowColors.muted),
                ),
              ),
              if (i.rating != null)
                Text(
                  '★ ${i.rating!.toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 11, color: WowColors.muted),
                ),
            ],
          ),
          if (widget.reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                widget.reason!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10, color: WowColors.success),
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {this.icon});
  final String text;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: .6),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) Icon(icon, size: 11, color: WowColors.accent),
        Text(
          text,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

Future<String?> askCollectionName(
  BuildContext context, {
  String initial = '我的片单',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('保存片单'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(labelText: '片单名称'),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.pop(context, v.trim());
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            if (controller.text.trim().isNotEmpty)
              Navigator.pop(context, controller.text.trim());
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  // Dialog route finishes its exit animation before disposing its controller.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}
