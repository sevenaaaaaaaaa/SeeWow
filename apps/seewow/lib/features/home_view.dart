import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/cinema_widgets.dart';
import '../design/tokens.dart';
import '../design/skin.dart';
import '../domain/catalog_category.dart';
import '../domain/media_item.dart';

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onPlay,
    this.onAgent,
    this.onSources,
    this.onLibrary,
    this.onLongPull,
  });
  final LibraryStore store;
  final ValueChanged<MediaItem> onOpen, onPlay;
  final ValueChanged<String>? onAgent;
  final VoidCallback? onSources, onLibrary;
  final VoidCallback? onLongPull;
  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final _prompt = TextEditingController();
  double _pull = 0;
  bool _spaceTriggered = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification is ScrollEndNotification) {
      _pull = 0;
      _spaceTriggered = false;
      return false;
    }
    final metrics = notification.metrics;
    // Clamping physics keeps pixels at the top and reports negative
    // overscroll, while bouncing physics moves pixels below the minimum.
    if (notification is OverscrollNotification &&
        notification.overscroll < 0 &&
        metrics.extentBefore <= 0) {
      _pull += -notification.overscroll;
    } else if (metrics.pixels < metrics.minScrollExtent) {
      _pull = metrics.minScrollExtent - metrics.pixels;
    }
    if (!_spaceTriggered && _pull > 180) {
      _spaceTriggered = true;
      widget.onLongPull?.call();
    }
    return false;
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  void _send() {
    if (_prompt.text.trim().isNotEmpty)
      widget.onAgent?.call(_prompt.text.trim());
  }

  Future<void> _refresh() async {
    await widget.store.refreshAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('片库已刷新'), duration: Duration(seconds: 1)),
    );
  }

  Widget _shelf(String title, String subtitle, List<MediaItem> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 30),
        SectionTitle(title, subtitle: subtitle),
        const SizedBox(height: 16),
        SizedBox(
          height: 310,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (_, n) => SizedBox(
              width: 160,
              child: FilmCard(
                item: items[n],
                store: widget.store,
                onOpen: () => widget.onOpen(items[n]),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final store = widget.store;
      final picks = store.recommendations(limit: 12);
      final featured =
          picks.firstOrNull?.item ??
          store.movies.firstOrNull ??
          store.items.firstOrNull;
      final recent = [...store.movies]
        ..sort(
          (a, b) => (b.addedAt ?? DateTime(1970)).compareTo(
            a.addedAt ?? DateTime(1970),
          ),
        );
      final documentaries = filterCategory(
        store.items,
        CatalogCategory.documentary,
      ).take(12).toList();
      final shortDramas = <MediaItem>[];
      final seenShows = <String>{};
      for (final item in filterCategory(
        store.items,
        CatalogCategory.shortDrama,
      )) {
        final key = item.showTitle ?? item.displayTitle;
        if (seenShows.add(key)) shortDramas.add(item);
        if (shortDramas.length >= 12) break;
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;
          final pad = compact ? 20.0 : 32.0;
          return NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(pad, 24, pad, 48),
                children: [
                  PageIntro(
                    eyebrow: 'YOUR PERSONAL CINEMA',
                    title: '把今晚，留给好电影。',
                    description: '你的收藏、观看记录和每一次偏好，都让下一部更合心意。',
                    action: OutlinedButton.icon(
                      onPressed: () => _preferences(context),
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('调整我的口味'),
                    ),
                  ),
                  if (widget.onLongPull != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '继续下拉，进入解耦空间',
                        style: TextStyle(fontSize: 10, color: WowColors.muted),
                      ),
                    ),
                  const SizedBox(height: 24),
                  if (featured == null)
                    CinemaPanel(
                      child: EmptyCinema(
                        icon: Icons.video_library_outlined,
                        title: '你的私人影院，从第一部开始',
                        description:
                            '连接本地文件夹、NAS 或网盘 WebDAV。影片会汇入同一个片库，推荐也从你的真实收藏开始。',
                        action: FilledButton.icon(
                          onPressed: widget.onSources,
                          icon: const Icon(Icons.add),
                          label: const Text('连接第一个片源'),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height:
                          (compact ? 380 : 360) +
                          (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(
                                0,
                                2,
                              ) *
                              240,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(
                          WowSkin.I.spec.radius,
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FilmArtwork(item: featured, landscape: true),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  stops: [0, .5, 1],
                                  colors: [
                                    Color(0xF5101314),
                                    Color(0xBB101314),
                                    Color(0x11101314),
                                  ],
                                ),
                              ),
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Color(0xDD101314),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.all(compact ? 24 : 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.auto_awesome_rounded,
                                        color: Colors.white70,
                                        size: 15,
                                      ),
                                      const SizedBox(width: 8),
                                      Eyebrow(
                                        'TONIGHT’S PICK',
                                        color: Colors.white70,
                                      ),
                                      const Spacer(),
                                      if (!compact)
                                        const Eyebrow('FROM YOUR LIBRARY'),
                                    ],
                                  ),
                                  const Spacer(),
                                  Text(
                                    featured.libraryTitle,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: compact ? 32 : 42,
                                      height: 1.12,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                      letterSpacing: -1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    [
                                      if (featured.year != null)
                                        '${featured.year}',
                                      ...featured.genres.take(2),
                                      if (featured.duration > 0)
                                        '${(featured.duration / 60).ceil()} 分钟',
                                      if (featured.quality.isNotEmpty)
                                        featured.quality,
                                    ].join('  ·  '),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFCDCFCC),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 480,
                                    ),
                                    child: Text(
                                      featured.overview.isEmpty
                                          ? '从你的片库出发，发现下一部值得投入的电影。'
                                          : featured.overview,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.7,
                                        color: Color(0xFFC4C6C2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.white,
                                          foregroundColor: const Color(
                                            0xFF121318,
                                          ),
                                        ),
                                        onPressed: () =>
                                            widget.onPlay(featured),
                                        icon: const Icon(
                                          Icons.play_arrow_rounded,
                                        ),
                                        label: Text(
                                          featured.position > 30 &&
                                                  !featured.watched
                                              ? '继续播放'
                                              : '开始观看',
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.white,
                                          side: const BorderSide(
                                            color: Colors.white38,
                                          ),
                                        ),
                                        onPressed: () =>
                                            store.toggleWatchlist(featured),
                                        icon: Icon(
                                          store.taste.watchlist.contains(
                                                featured.id,
                                              )
                                              ? Icons.check
                                              : Icons.add,
                                          size: 18,
                                        ),
                                        label: Text(
                                          store.taste.watchlist.contains(
                                                featured.id,
                                              )
                                              ? '已加入待看'
                                              : '加入待看',
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: () =>
                                            widget.onOpen(featured),
                                        tooltip: '影片详情',
                                        icon: const Icon(
                                          Icons.info_outline,
                                          color: Colors.white,
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
                    ),
                  const SizedBox(height: 18),
                  CinemaPanel(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: WowColors.accent.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.auto_awesome,
                                color: WowColors.accent,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _prompt,
                                onSubmitted: (_) => _send(),
                                decoration: const InputDecoration(
                                  hintText: '今晚想看什么？也可以让我整理片库…',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            IconButton.filled(
                              onPressed: _send,
                              tooltip: '交给 Agent',
                              icon: const Icon(
                                Icons.arrow_upward_rounded,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final prompt in [
                              '按我的口味生成片单',
                              '找一部轻松的电影',
                              '检查片库重复与缺失信息',
                            ])
                              ActionChip(
                                label: Text(
                                  prompt,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () => widget.onAgent?.call(prompt),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (store.continueWatching.isNotEmpty) ...[
                    const SizedBox(height: 30),
                    SectionTitle(
                      '继续你的故事',
                      subtitle: '回到上次停下的地方',
                      action: TextButton(
                        onPressed: widget.onLibrary,
                        child: const Text('查看片库 →'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height:
                          164 +
                          (MediaQuery.textScalerOf(context).scale(1) - 1).clamp(
                                0,
                                2,
                              ) *
                              70,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: store.continueWatching.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 14),
                        itemBuilder: (_, n) {
                          final i = store.continueWatching[n];
                          return SizedBox(
                            width: 244,
                            child: Material(
                              color: WowColors.panel,
                              borderRadius: BorderRadius.circular(
                                WowSkin.I.spec.posterRadius,
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () => widget.onPlay(i),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      height: 110,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          FilmArtwork(item: i, landscape: true),
                                          const Center(
                                            child: Icon(
                                              Icons.play_circle_fill_rounded,
                                              size: 34,
                                              color: Colors.white,
                                            ),
                                          ),
                                          Positioned(
                                            bottom: 0,
                                            left: 0,
                                            right: 0,
                                            child: LinearProgressIndicator(
                                              value: i.progress,
                                              minHeight: 3,
                                              color: WowColors.accent,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        12,
                                        8,
                                        12,
                                        0,
                                      ),
                                      child: Text(
                                        i.displayTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: 12,
                                        top: 3,
                                      ),
                                      child: Text(
                                        i.duration > 0
                                            ? '剩余 ${(i.remainingSeconds / 60).ceil()} 分钟'
                                            : '继续播放',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: WowColors.muted,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (recent.isNotEmpty)
                    _shelf('最近加入', '刚入库的影片，下拉可刷新', recent.take(12).toList()),
                  if (documentaries.isNotEmpty)
                    _shelf('纪录片', '纪实、自然与人文片单', documentaries),
                  if (shortDramas.isNotEmpty)
                    _shelf('短剧', '单集 20 分钟内 · 竖屏短剧优先', shortDramas),
                  const SizedBox(height: 30),
                  SectionTitle(
                    '为你，再多一点发现',
                    subtitle: store.taste.genres.isEmpty
                        ? '根据喜欢与观看记录在本地排序 · 可在「调整我的口味」设置偏好'
                        : '偏爱 ${store.taste.genres.join(' / ')} · 不感兴趣的影片会退出推荐',
                  ),
                  const SizedBox(height: 18),
                  if (picks.isEmpty)
                    const CinemaPanel(
                      child: Text('暂无未看推荐。添加更多影片，或在媒体库恢复不感兴趣的条目。'),
                    )
                  else
                    SizedBox(
                      height: 310,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: picks.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 16),
                        itemBuilder: (_, n) => SizedBox(
                          width: 160,
                          child: FilmCard(
                            item: picks[n].item,
                            store: store,
                            reason: picks[n].reason,
                            onOpen: () => widget.onOpen(picks[n].item),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
  Future<void> _preferences(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('你的电影口味'),
      content: SizedBox(
        width: 430,
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '选择你喜欢的类型。喜欢、已看和不感兴趣也会影响之后的推荐。',
                style: WowType.body(13, color: WowColors.muted),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in {
                    '科幻',
                    '剧情',
                    '悬疑',
                    '喜剧',
                    '冒险',
                    '动画',
                    '爱情',
                    '纪录片',
                    '惊悚',
                    ...widget.store.items.expand((i) => i.genres),
                  })
                    FilterChip(
                      label: Text(g),
                      selected: widget.store.taste.genres.contains(g),
                      onSelected: (_) => widget.store.toggleGenre(g),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '已屏蔽 ${widget.store.taste.dislikedIds.length} 部影片。可从媒体库卡片菜单恢复。',
                style: WowType.body(12, color: WowColors.muted),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    ),
  );
}
