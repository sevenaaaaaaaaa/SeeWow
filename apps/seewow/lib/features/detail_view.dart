import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/cinema_widgets.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../downloads/download_manager.dart';
import '../downloads/downloads_view.dart';
import 'metadata_dialog.dart';
import 'metadata_editor.dart';
import 'metadata_facts.dart';
import 'metadata_language_batch.dart';
import 'custom_scraper_view.dart';
import 'cover_generation_view.dart';

class DetailView extends StatelessWidget {
  const DetailView({
    super.key,
    required this.item,
    required this.store,
    required this.onPlay,
    this.downloads,
  });
  final MediaItem item;
  final LibraryStore store;
  final ValueChanged<MediaItem> onPlay;
  final DownloadManager? downloads;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: downloads == null
        ? store
        : Listenable.merge([store, downloads!]),
    builder: (context, _) {
      final current = store.current(item);
      final heroButton = OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: .28),
        side: BorderSide(color: Colors.white.withValues(alpha: .35)),
      );
      final episodes = item.kind == MediaKind.episode
          ? store.episodes
                .where(
                  (e) =>
                      (e.showTitle ?? e.title) ==
                      (item.showTitle ?? item.title),
                )
                .toList()
          : <MediaItem>[];
      episodes.sort(
        (a, b) => ((a.season ?? 0) * 10000 + (a.episode ?? 0)).compareTo(
          (b.season ?? 0) * 10000 + (b.episode ?? 0),
        ),
      );
      final related = store
          .recommendations(limit: 10)
          .where((p) => current.kind != MediaKind.audio && p.item.id != item.id)
          .toList();
      return Scaffold(
        backgroundColor: WowColors.ink,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxWidth < 700;
              final pad = compact ? 20.0 : 40.0;
              return ListView(
                children: [
                  SizedBox(
                    height: compact ? 440 : 470,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FilmArtwork(item: current, landscape: true),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Color(0xF0101212),
                                Color(0x88101212),
                                Color(0x33101212),
                              ],
                            ),
                          ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Color(0xFF101010), Colors.transparent],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          left: pad,
                          child: IconButton.filledTonal(
                            tooltip: '返回',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back),
                          ),
                        ),
                        Positioned(
                          left: pad,
                          right: pad,
                          bottom: 28,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Eyebrow(
                                current.kind == MediaKind.episode
                                    ? 'FROM YOUR SERIES'
                                    : 'IN YOUR COLLECTION',
                                color: WowColors.accent,
                              ),
                              const SizedBox(height: 14),
                              Text(
                                current.libraryTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: compact ? 32 : 46,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                  height: 1.15,
                                  letterSpacing: -1,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                [
                                  if (current.year != null) '${current.year}',
                                  ...current.genres,
                                  if (current.duration > 0)
                                    '${(current.duration / 60).ceil()} 分钟',
                                  if (current.rating != null)
                                    '★ ${current.rating!.toStringAsFixed(1)}',
                                  if (current.quality.isNotEmpty)
                                    current.quality,
                                ].join('  ·  '),
                                style: const TextStyle(
                                  color: Color(0xFFCDCFCC),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 20),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  FilledButton.icon(
                                    onPressed: () => onPlay(current),
                                    icon: const Icon(Icons.play_arrow),
                                    label: Text(
                                      current.position > 30 && !current.watched
                                          ? '继续观看'
                                          : '开始观看',
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    style: heroButton,
                                    onPressed: () =>
                                        store.toggleWatchlist(current),
                                    icon: Icon(
                                      store.taste.watchlist.contains(current.id)
                                          ? Icons.bookmark
                                          : Icons.bookmark_add_outlined,
                                      size: 18,
                                    ),
                                    label: Text(
                                      store.taste.watchlist.contains(current.id)
                                          ? '已加入待看'
                                          : '加入待看',
                                    ),
                                  ),
                                  if (downloads != null)
                                    OutlinedButton.icon(
                                      style: heroButton,
                                      onPressed: () async {
                                        final manager = downloads!;
                                        if (manager.hasOffline(current.id)) {
                                          onPlay(current);
                                          return;
                                        }
                                        final sourceName =
                                            store.sources
                                                .where(
                                                  (s) =>
                                                      s.id == current.sourceId,
                                                )
                                                .firstOrNull
                                                ?.name ??
                                            '本地';
                                        final started = await showDownloadSheet(
                                          context,
                                          manager: manager,
                                          item: current,
                                          sourceName: sourceName,
                                        );
                                        if (started == true &&
                                            context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                const SnackBar(
                                                  content: Text('已加入离线缓存'),
                                                ),
                                              );
                                        }
                                      },
                                      icon: Icon(
                                        downloads!.hasOffline(current.id)
                                            ? Icons.offline_pin
                                            : Icons
                                                  .download_for_offline_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        downloads!.hasOffline(current.id)
                                            ? '离线播放'
                                            : '缓存到本地',
                                      ),
                                    ),
                                  OutlinedButton.icon(
                                    style: heroButton,
                                    onPressed: () => store.setFavorite(
                                      current,
                                      !current.isFavorite,
                                    ),
                                    icon: Icon(
                                      current.isFavorite
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      size: 18,
                                    ),
                                    label: Text(
                                      current.isFavorite ? '已喜欢' : '喜欢',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(pad, 8, pad, 48),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (current.progress > 0) ...[
                          LinearProgressIndicator(
                            value: current.progress,
                            minHeight: 3,
                            color: WowColors.accent,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            current.watched
                                ? '已经看过'
                                : '已看 ${(current.progress * 100).round()}% · 剩余 ${(current.remainingSeconds / 60).ceil()} 分钟',
                            style: TextStyle(
                              color: WowColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 26),
                        ],
                        SectionTitle(
                          current.kind == MediaKind.audio ? '曲目信息' : '故事从这里开始',
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Text(
                            current.overview.isEmpty
                                ? '此条目暂无简介。可使用「匹配影片信息」搜索并预览 TMDB 元数据。'
                                : current.overview,
                            style: WowType.body(
                              14,
                              color: WowColors.muted,
                              height: 1.9,
                            ),
                          ),
                        ),
                        if (current.metadata != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: MetadataFacts(metadata: current.metadata!),
                          ),
                        if (current.hasGeneratedCover)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'AI 配图 · ${current.metadata!.generatedCover['model']} · 非官方海报',
                            ),
                          ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            if (current.kind != MediaKind.audio)
                              TextButton.icon(
                                onPressed: () => matchCustomMetadata(
                                  context,
                                  store,
                                  current,
                                ),
                                icon: const Icon(Icons.api_outlined, size: 17),
                                label: const Text('自定义 API 匹配'),
                              ),
                            if (current.kind != MediaKind.audio)
                              TextButton.icon(
                                onPressed: current.aiAllowed
                                    ? () => generateMediaCover(
                                        context,
                                        store,
                                        current,
                                      )
                                    : null,
                                icon: const Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 17,
                                ),
                                label: const Text('AI 生成封面'),
                              ),
                            TextButton.icon(
                              onPressed: () => manageMetadataLanguages(
                                context,
                                store,
                                [current],
                              ),
                              icon: const Icon(Icons.language, size: 17),
                              label: const Text('多语言资料与本机补译'),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  editMetadata(context, store, current),
                              icon: const Icon(Icons.edit_outlined, size: 17),
                              label: const Text('编辑媒体资料'),
                            ),
                            TextButton.icon(
                              onPressed: () => store.markWatched([
                                current,
                              ], !current.watched),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 17,
                              ),
                              label: Text(current.watched ? '标记为未看' : '标记为已看'),
                            ),
                            TextButton.icon(
                              onPressed: () => store.setDisliked(
                                current,
                                !store.taste.dislikedIds.contains(current.id),
                              ),
                              icon: const Icon(
                                Icons.visibility_off_outlined,
                                size: 17,
                              ),
                              label: Text(
                                store.taste.dislikedIds.contains(current.id)
                                    ? '恢复推荐'
                                    : '不感兴趣',
                              ),
                            ),
                            if (current.kind != MediaKind.audio)
                              TextButton.icon(
                                onPressed: current.kind == MediaKind.audio
                                    ? null
                                    : () => matchMetadata(
                                        context,
                                        store,
                                        current,
                                      ),
                                icon: const Icon(Icons.manage_search, size: 17),
                                label: Text(
                                  current.metadata == null
                                      ? '匹配影片信息'
                                      : '重新匹配影片信息',
                                ),
                              ),
                            TextButton.icon(
                              onPressed: () async {
                                final name = await askCollectionName(
                                  context,
                                  initial: current.libraryTitle,
                                );
                                if (name != null)
                                  await store.createCollection(name, [
                                    current.id,
                                  ]);
                              },
                              icon: const Icon(Icons.playlist_add, size: 17),
                              label: const Text('保存为片单'),
                            ),
                          ],
                        ),
                        if (episodes.isNotEmpty) ...[
                          const SizedBox(height: 30),
                          const SectionTitle('逐集观看'),
                          const SizedBox(height: 14),
                          for (final e in episodes)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: CinemaPanel(
                                padding: const EdgeInsets.all(4),
                                child: ListTile(
                                  onTap: () => onPlay(e),
                                  leading: Icon(
                                    e.watched
                                        ? Icons.check_circle_outline
                                        : Icons.play_circle_outline,
                                    color: WowColors.accent,
                                  ),
                                  title: Text(
                                    e.displayTitle,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    e.duration <= 0
                                        ? '时长未知'
                                        : '${(e.duration / 60).round()} 分钟 · 已看 ${(e.progress * 100).round()}%',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: WowColors.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                        const SizedBox(height: 30),
                        const SectionTitle('媒体信息'),
                        const SizedBox(height: 14),
                        CinemaPanel(
                          child: Wrap(
                            spacing: 40,
                            runSpacing: 20,
                            children: [
                              _info(
                                '来源',
                                store.sources
                                        .where((s) => s.id == current.sourceId)
                                        .firstOrNull
                                        ?.name ??
                                    '来源已移除',
                              ),
                              _info(
                                '文件格式',
                                current.container.isEmpty
                                    ? '未知'
                                    : current.container,
                              ),
                              _info(
                                '文件大小',
                                current.fileSize <= 0
                                    ? '未知'
                                    : '${(current.fileSize / 1024 / 1024).round()} MB',
                              ),
                              _info(
                                '文件名',
                                Uri.tryParse(current.locator)
                                        ?.pathSegments
                                        .lastOrNull ??
                                    current.title,
                              ),
                            ],
                          ),
                        ),
                        if (related.isNotEmpty) ...[
                          const SizedBox(height: 32),
                          const SectionTitle('也许下一部，会是它'),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 290,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: related.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 16),
                              itemBuilder: (_, n) => SizedBox(
                                width: 150,
                                child: FilmCard(
                                  item: related[n].item,
                                  store: store,
                                  reason: related[n].reason,
                                  onOpen: () => Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute<void>(
                                      builder: (_) => DetailView(
                                        item: related[n].item,
                                        store: store,
                                        onPlay: onPlay,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
  Widget _info(String label, String value) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 420),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: WowColors.muted)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}
