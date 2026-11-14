import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/cinema_widgets.dart';
import '../design/tokens.dart';
import '../domain/catalog_category.dart';
import '../domain/media_item.dart';

/// A dedicated short-drama surface: vertical cards, whole series first, and a
/// queue that keeps playing after the current episode ends.
///
/// The feed elsewhere treats short drama as one filter among many. Here it is
/// the whole screen, which is what "an obvious way in" means.
class ShortDramaView extends StatelessWidget {
  const ShortDramaView({
    super.key,
    required this.store,
    required this.onPlayQueue,
    this.onSources,
  });

  final LibraryStore store;

  /// Plays [queue] from [index] and keeps rolling to the next episode.
  final void Function(List<MediaItem> queue, int index) onPlayQueue;
  final VoidCallback? onSources;

  @override
  Widget build(BuildContext context) {
    final seasons = _group(store.items);
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
      children: [
        PageIntro(
          eyebrow: 'SHORT DRAMA',
          title: '竖屏短剧。',
          description: '单集 20 分钟以内，播完自动接下一集。上下滑动挑剧，点开就连着看。',
          action: OutlinedButton.icon(
            onPressed: seasons.isEmpty
                ? null
                : () => onPlayQueue(_flatten(seasons), 0),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('从第一部开始'),
          ),
        ),
        const SizedBox(height: 28),
        if (seasons.isEmpty)
          CinemaPanel(
            child: EmptyCinema(
              icon: Icons.movie_filter_outlined,
              title: '还没有短剧',
              description: '片源里的竖屏短剧、微短剧，或单集 20 分钟以内的剧集会自动出现在这里。',
              action: FilledButton.icon(
                onPressed: onSources,
                icon: const Icon(Icons.add),
                label: const Text('连接片源'),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = (constraints.maxWidth / 190).floor().clamp(2, 8);
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 20,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.52,
                ),
                itemCount: seasons.length,
                itemBuilder: (context, index) {
                  final season = seasons[index];
                  return _DramaCard(
                    store: store,
                    title: season.title,
                    episodes: season.episodes,
                    onOpen: () => onPlayQueue(season.episodes, 0),
                  );
                },
              );
            },
          ),
      ],
    );
  }

  List<_DramaSeason> _group(List<MediaItem> library) {
    final candidates = filterCategory(library, CatalogCategory.shortDrama);
    final byTitle = <String, List<MediaItem>>{};
    for (final item in candidates) {
      final key = (item.showTitle ?? item.displayTitle).trim();
      if (key.isEmpty) continue;
      byTitle.putIfAbsent(key, () => []).add(item);
    }
    final seasons = byTitle.entries.map((e) {
      final episodes = [...e.value]
        ..sort((a, b) {
          final season = (a.season ?? 0).compareTo(b.season ?? 0);
          return season == 0
              ? (a.episode ?? 0).compareTo(b.episode ?? 0)
              : season;
        });
      return _DramaSeason(e.key, episodes);
    }).toList();
    seasons.sort((a, b) {
      final added = (b.latest.addedAt ?? DateTime(1970)).compareTo(
        a.latest.addedAt ?? DateTime(1970),
      );
      return added == 0 ? a.title.compareTo(b.title) : added;
    });
    return seasons;
  }

  List<MediaItem> _flatten(List<_DramaSeason> seasons) =>
      [for (final s in seasons) ...s.episodes];
}

class _DramaSeason {
  _DramaSeason(this.title, this.episodes);
  final String title;
  final List<MediaItem> episodes;
  MediaItem get latest => episodes.last;
}

class _DramaCard extends StatefulWidget {
  const _DramaCard({
    required this.store,
    required this.title,
    required this.episodes,
    required this.onOpen,
  });

  final LibraryStore store;
  final String title;
  final List<MediaItem> episodes;
  final VoidCallback onOpen;

  @override
  State<_DramaCard> createState() => _DramaCardState();
}

class _DramaCardState extends State<_DramaCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final current = widget.store.current(widget.episodes.first);
    final minutes = current.duration > 0
        ? '${(current.duration / 60).round()} 分钟/集'
        : '时长未知';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _DramaPoster(item: current),
                    Positioned(
                      left: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${widget.episodes.length} 集',
                          style: WowType.monoLabel(
                            10,
                            color: Colors.white.withValues(alpha: 0.9),
                            spacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                    AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: const Duration(milliseconds: 160),
                      child: Container(
                        color: Colors.black38,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 46,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WowType.display(14, FontWeight.w600, spacing: -0.2),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.episodes.length} 集 · $minutes · 自动连播',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WowType.monoLabel(10, color: WowColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// A 9:16 cover for a vertical drama. Poster artwork is landscape-first in most
/// libraries, so a plain crop would cut faces in half; the fallback keeps the
/// title readable when there is no artwork at all.
class _DramaPoster extends StatelessWidget {
  const _DramaPoster({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final url = item.posterUrl;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [WowColors.panel, WowColors.ink],
        ),
      ),
      child: url == null || url.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  item.displayTitle,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: WowType.display(15, FontWeight.w600, spacing: -0.2),
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              headers: item.artworkHeaders(item.posterUrl),
              errorBuilder: (context, error, stack) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    item.displayTitle,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: WowType.display(15, FontWeight.w600, spacing: -0.2),
                  ),
                ),
              ),
            ),
    );
  }
}
