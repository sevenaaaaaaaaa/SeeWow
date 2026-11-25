import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../downloads/download_manager.dart';
import '../design/cinema_widgets.dart';
import '../design/liquid_glass.dart';
import '../design/skeleton.dart';
import '../design/tokens.dart';
import '../design/skin.dart';
import '../domain/library_intelligence.dart';
import '../domain/catalog_category.dart';
import '../domain/media_item.dart';
import 'batch_scrape_view.dart';
import 'metadata_language_batch.dart';

class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.store,
    required this.onOpen,
    this.initialText = '',
    this.collection,
    this.initialKind,
    this.initialWatch = WatchFilter.all,
    this.onSources,
    this.onInteract,
    this.downloads,
    this.onPlay,
    this.onFrames,
  });
  final LibraryStore store;
  final ValueChanged<MediaItem> onOpen;

  /// Optional: play straight from a poster instead of opening the detail page.
  final ValueChanged<MediaItem>? onPlay;
  final VoidCallback? onSources;

  /// Opens the saved-frame list. Null hides the entry in the filter strip.
  final VoidCallback? onFrames;

  /// Fired on any pointer-down: a shake right after a tap is never intended.
  final VoidCallback? onInteract;

  /// Optional: when present, a selection can be cached to disk in one go.
  final DownloadManager? downloads;
  final String initialText;
  final FilmCollection? collection;
  final MediaKind? initialKind;
  final WatchFilter initialWatch;
  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  late final TextEditingController _search;
  String? _source, _genre;
  MediaKind? _kind;
  CatalogCategory _category = CatalogCategory.all;
  late WatchFilter _watch;
  LibrarySort _sort = LibrarySort.recent;
  bool _list = false, _selecting = false, _audit = false, _offline = false;
  final Set<String> _selected = {};
  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initialText);
    _kind = widget.initialKind;
    _watch = widget.initialWatch;
    if (widget.initialKind == MediaKind.audio) _list = true;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final store = widget.store;
        final pad = box.maxWidth < 700 ? 20.0 : 32.0;
        var items = LibraryQuery(
          text: _search.text,
          sourceId: _source,
          genre: _genre,
          kind: _kind,
          watch: _watch,
          sort: _sort,
        ).apply(store.items, store.taste);
        if (widget.collection != null)
          items = items
              .where((i) => widget.collection!.itemIds.contains(i.id))
              .toList();
        if (_category != CatalogCategory.all) {
          items = filterCategory(items, _category);
        }
        final audit = LibraryAudit(store.items);
        if (_audit) {
          final ids = {
            ...audit.duplicates.expand((g) => g.map((i) => i.id)),
            ...audit.missingMetadata.map((i) => i.id),
          };
          items = items.where((i) => ids.contains(i.id)).toList();
        }
        final downloads = widget.downloads;
        final cachedIds = downloads == null
            ? const <String>{}
            : downloads.cachedItemIds(store.items);
        final offlineCount = cachedIds.length;
        if (_offline && downloads != null) {
          items = items.where((i) => cachedIds.contains(i.id)).toList();
        }
        final genres = store.items.expand((i) => i.genres).toSet().toList()
          ..sort();
        final columns =
            ((box.maxWidth - pad * 2) / (WowSkin.I.spec.compact ? 148 : 180))
                .floor()
                .clamp(2, 8);
        final selectedItems = store.items
            .where((i) => _selected.contains(i.id))
            .toList();
        return Listener(
          onPointerDown: (_) => widget.onInteract?.call(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(pad, 24, pad, 20),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PageIntro(
                        title:
                            widget.collection?.name ??
                            (widget.initialKind == MediaKind.audio
                                ? '你的音乐库'
                                : '你的媒体库'),
                        description:
                            widget.collection?.description.isNotEmpty == true
                            ? widget.collection!.description
                            : '${store.movies.length} 部电影 · ${store.series.length} 部剧集 · ${store.items.where((i) => i.kind == MediaKind.audio).length} 首音乐 · ${store.sources.length} 个来源，统一管理。',
                        action: OutlinedButton.icon(
                          onPressed: widget.onSources,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('连接片源'),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: '搜索片名、年份、类型、简介…',
                                prefixIcon: const Icon(Icons.search, size: 19),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: '清空搜索',
                                        onPressed: () =>
                                            setState(_search.clear),
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton(
                            tooltip: _list ? '海报视图' : '列表视图',
                            onPressed: () => setState(() => _list = !_list),
                            icon: Icon(
                              _list
                                  ? Icons.grid_view_rounded
                                  : Icons.view_list_rounded,
                            ),
                          ),
                          if (items.isNotEmpty)
                            IconButton(
                              tooltip: '结果保存为片单',
                              onPressed: () => _save(items),
                              icon: const Icon(Icons.playlist_add, size: 20),
                            ),
                          IconButton(
                            tooltip: '批量刮削',
                            onPressed: () => runBatchScrape(
                              context,
                              widget.store,
                              items,
                            ),
                            icon: const Icon(Icons.auto_awesome_motion, size: 20),
                          ),
                          IconButton(
                            tooltip: '批量选择',
                            isSelected: _selecting,
                            onPressed: () => setState(() {
                              _selecting = !_selecting;
                              _selected.clear();
                            }),
                            icon: const Icon(Icons.checklist_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // 筛选条只占一行：分类、筛选、待整理、已缓存、保存片单
                      // 全在这条横滚带上。五个下拉原本各占一格、手机上排成
                      // 三行，把结果压到半屏以下，现在收进「筛选」面板。
                      SizedBox(
                        height: 34,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            // 收藏过的画面是用户自己的东西，不该藏在最右端：
                            // 放在横滚带第一格，一进片库就看得见。
                            if (widget.onFrames != null) ...[
                              _chip(
                                label: '精彩帧',
                                icon: Icons.photo_library_outlined,
                                onTap: widget.onFrames!,
                              ),
                              const SizedBox(width: 6),
                            ],
                            for (final category in CatalogCategory.values) ...[
                              _chip(
                                label: categoryLabel(category),
                                selected: _category == category,
                                onTap: () =>
                                    setState(() => _category = category),
                              ),
                              const SizedBox(width: 6),
                            ],
                            _chip(
                              label: activeFilters == 0
                                  ? '筛选'
                                  : '筛选 · $activeFilters',
                              icon: Icons.tune_rounded,
                              selected: activeFilters > 0,
                              onTap: () => _openFilters(store, genres),
                            ),
                            const SizedBox(width: 6),
                            _chip(
                              label:
                                  '待整理 · ${audit.duplicates.length}/${audit.missingMetadata.length}',
                              icon: Icons.fact_check_outlined,
                              selected: _audit,
                              onTap: () => setState(() => _audit = !_audit),
                            ),
                            if (downloads != null) ...[
                              const SizedBox(width: 6),
                              _chip(
                                label: '已缓存 · $offlineCount',
                                icon: Icons.download_done_outlined,
                                selected: _offline,
                                onTap: () =>
                                    setState(() => _offline = !_offline),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_category == CatalogCategory.shortDrama)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            '短剧模式 · 单集 20 分钟内优先 · ${items.length} 部',
                            style: TextStyle(
                              fontSize: 11,
                              color: WowColors.accent,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${items.length} 个条目',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: WowColors.muted,
                            ),
                          ),
                          if (_audit)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '重复 ${audit.duplicates.length} 组 · 缺信息 ${audit.missingMetadata.length} 项',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: WowColors.accent,
                                ),
                              ),
                            ),
                          const Spacer(),
                          if (activeFilters > 0)
                            TextButton(
                              onPressed: () => setState(() {
                                _source = null;
                                _genre = null;
                                _kind = null;
                                _watch = WatchFilter.all;
                                _sort = LibrarySort.recent;
                              }),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              child: const Text('清除筛选'),
                            ),
                        ],
                      ),
                      if (_selecting)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: CinemaPanel(
                            padding: const EdgeInsets.all(12),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '已选 ${_selected.length} 项',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _selected.clear();
                                    _selected.addAll(items.map((i) => i.id));
                                  }),
                                  child: const Text('选择当前结果'),
                                ),
                                TextButton(
                                  onPressed: selectedItems.isEmpty
                                      ? null
                                      : () => store.markWatched(
                                          selectedItems,
                                          true,
                                        ),
                                  child: const Text('标为已看'),
                                ),
                                TextButton(
                                  onPressed: selectedItems.isEmpty
                                      ? null
                                      : () => store.markWatched(
                                          selectedItems,
                                          false,
                                        ),
                                  child: const Text('标为未看'),
                                ),
                                TextButton(
                                  onPressed: selectedItems.isEmpty
                                      ? null
                                      : () => _save(selectedItems),
                                  child: const Text('保存片单'),
                                ),
                                TextButton.icon(
                                  onPressed:
                                      selectedItems.isEmpty ||
                                          widget.downloads == null
                                      ? null
                                      : () => _cacheSelected(selectedItems),
                                  icon: const Icon(
                                    Icons.download_for_offline_outlined,
                                    size: 16,
                                  ),
                                  label: const Text('缓存选中'),
                                ),
                                TextButton.icon(
                                  onPressed: selectedItems.isEmpty
                                      ? null
                                      : () => manageMetadataLanguages(
                                          context,
                                          store,
                                          selectedItems,
                                        ),
                                  icon: const Icon(Icons.translate, size: 17),
                                  label: const Text('多语言采集／本机补译'),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (items.isEmpty && store.scanning)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 24),
                  sliver: LibrarySkeleton(columns: columns),
                )
              else if (items.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyCinema(
                    icon: Icons.video_library_outlined,
                    title: store.items.isEmpty ? '片库还空着' : '没有匹配的影片',
                    description: store.items.isEmpty
                        ? '连接片源后，电影、剧集与观看进度会出现在这里。'
                        : _offline
                        ? '还没有可离线播放的缓存：选中影片或整个片单后点「缓存选中」，就能在这里直接找到。'
                        : '试试更短的关键词，或调整来源、类型和观看状态。',
                    // A no-result screen with no button is a dead end: the
                    // user can see that nothing matched and has no way back
                    // except editing six filters one at a time.
                    action: store.items.isEmpty
                        ? GlassButton(
                            label: '连接片源',
                            icon: Icons.add_rounded,
                            prominent: true,
                            onTap: widget.onSources,
                          )
                        : GlassButton(
                            label: '清除筛选',
                            icon: Icons.filter_alt_off_outlined,
                            onTap: _clearFilters,
                          ),
                  ),
                )
              else if (_list)
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  sliver: SliverList.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final i = items[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: WowColors.panel,
                          borderRadius: BorderRadius.circular(
                            WowSkin.I.spec.posterRadius,
                          ),
                          child: ListTile(
                            onTap: () =>
                                _selecting ? _toggle(i.id) : widget.onOpen(i),
                            leading: _selecting
                                ? Checkbox(
                                    value: _selected.contains(i.id),
                                    onChanged: (_) => _toggle(i.id),
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: SizedBox(
                                      width: 38,
                                      height: 52,
                                      child: FilmArtwork(item: i),
                                    ),
                                  ),
                            title: Text(
                              i.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              i.kind == MediaKind.audio
                                  ? [
                                      if (i.artist.isNotEmpty) i.artist,
                                      if (i.album.isNotEmpty) i.album,
                                      store.sources
                                              .where((s) => s.id == i.sourceId)
                                              .firstOrNull
                                              ?.name ??
                                          '',
                                    ].where((s) => s.isNotEmpty).join(' · ')
                                  : '${i.year ?? '年份未知'} · ${store.sources.where((s) => s.id == i.sourceId).firstOrNull?.name ?? '未知来源'} · ${i.watched ? '已看' : '未看完'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: WowColors.muted,
                              ),
                            ),
                            trailing: i.kind == MediaKind.audio
                                ? (i.duration > 0
                                      ? Text(
                                          _clockText(i.duration),
                                          style: WowType.monoLabel(11),
                                        )
                                      : null)
                                : IconButton(
                                    tooltip:
                                        store.taste.watchlist.contains(i.id)
                                        ? '移出待看'
                                        : '加入待看',
                                    onPressed: () => store.toggleWatchlist(i),
                                    icon: Icon(
                                      store.taste.watchlist.contains(i.id)
                                          ? Icons.bookmark_rounded
                                          : Icons.bookmark_border_rounded,
                                      size: 20,
                                    ),
                                  ),
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  sliver: SliverGrid.builder(
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 24,
                      childAspectRatio: .57,
                    ),
                    itemBuilder: (context, n) => FilmCard(
                      item: items[n],
                      store: store,
                      onOpen: () => widget.onOpen(items[n]),
                      onPlay: widget.onPlay == null
                          ? null
                          : () => widget.onPlay!(items[n]),
                      selectionMode: _selecting,
                      selected: _selected.contains(items[n].id),
                      onSelect: () => _toggle(items[n].id),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
        );
      },
    ),
  );

  /// Caches a whole selection (a season, a shelf) in one action, skipping
  /// anything already on disk.
  Future<void> _cacheSelected(List<MediaItem> items) async {
    final manager = widget.downloads;
    if (manager == null) return;
    var queued = 0;
    for (final item in items) {
      if (manager.isCached(item)) continue;
      final source = widget.store.sources
          .where((s) => s.id == item.sourceId)
          .firstOrNull;
      await manager.enqueue(
        item,
        source: source,
        sourceName: source?.name ?? '本地',
      );
      queued++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(queued == 0 ? '选中的影片都已缓存' : '已加入缓存队列 $queued 项'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Back to the whole library in one move.
  void _clearFilters() => setState(() {
    _search.clear();
    _source = null;
    _genre = null;
    _kind = null;
    _category = CatalogCategory.all;
    _watch = WatchFilter.all;
    _offline = false;
    _audit = false;
    _sort = LibrarySort.recent;
  });

  void _toggle(String id) => setState(() {
    if (!_selected.remove(id)) _selected.add(id);
  });
  Future<void> _save(List<MediaItem> items) async {
    final name = await askCollectionName(
      context,
      initial: _search.text.isEmpty ? '我的片单' : _search.text,
    );
    if (name != null) {
      await widget.store.createCollection(name, items.map((i) => i.id));
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('片单已保存，可在「我的片单」查看')));
    }
  }

  int get activeFilters =>
      (_source != null ? 1 : 0) +
      (_genre != null ? 1 : 0) +
      (_kind != null ? 1 : 0) +
      (_watch != WatchFilter.all ? 1 : 0) +
      (_sort != LibrarySort.recent ? 1 : 0);

  /// 筛选条上的小胶囊：图标可选，选中态沿用项目里的 ChoiceChip。
  Widget _chip({
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    IconData? icon,
  }) => ChoiceChip(
    label: Text(label, style: const TextStyle(fontSize: 11)),
    selected: selected,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    avatar: icon == null ? null : Icon(icon, size: 14),
    onSelected: (_) => onTap(),
  );

  /// 五个下拉进面板：手机上它们原来独占三行，把结果挤到半屏以下。
  Future<void> _openFilters(LibraryStore store, List<String> genres) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheet) {
          void touch(VoidCallback change) {
            setSheet(change);
            setState(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              20 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '筛选',
                  style: WowType.display(22, FontWeight.w500, spacing: -0.4),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _filter<String>('全部来源', _source, [
                      for (final s in store.sources)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ], (v) => touch(() => _source = v)),
                    _filter<String>('全部类型', _genre, [
                      for (final g in genres)
                        DropdownMenuItem(value: g, child: Text(g)),
                    ], (v) => touch(() => _genre = v)),
                    _filter<MediaKind>('全部媒体', _kind, const [
                      DropdownMenuItem(
                        value: MediaKind.movie,
                        child: Text('电影'),
                      ),
                      DropdownMenuItem(
                        value: MediaKind.episode,
                        child: Text('剧集'),
                      ),
                      DropdownMenuItem(
                        value: MediaKind.audio,
                        child: Text('音乐'),
                      ),
                    ], (v) => touch(() => _kind = v)),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<WatchFilter>(
                        initialValue: _watch,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          for (final f in WatchFilter.values)
                            DropdownMenuItem(
                              value: f,
                              child: Text(
                                _watchLabel(f),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                        ],
                        onChanged: (v) => touch(() => _watch = v!),
                      ),
                    ),
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<LibrarySort>(
                        initialValue: _sort,
                        isExpanded: true,
                        decoration: const InputDecoration(isDense: true),
                        items: [
                          for (final f in LibrarySort.values)
                            DropdownMenuItem(
                              value: f,
                              child: Text(switch (f) {
                                LibrarySort.recent => '最近添加',
                                LibrarySort.title => '片名排序',
                                LibrarySort.rating => '评分优先',
                                LibrarySort.year => '最新年份',
                              }, style: const TextStyle(fontSize: 12)),
                            ),
                        ],
                        onChanged: (v) => touch(() => _sort = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (activeFilters > 0)
                      TextButton(
                        onPressed: () => touch(() {
                          _source = null;
                          _genre = null;
                          _kind = null;
                          _watch = WatchFilter.all;
                          _sort = LibrarySort.recent;
                        }),
                        child: const Text('清除筛选'),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filter<T>(
    String label,
    T? value,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> onChanged,
  ) => SizedBox(
    width: 122,
    child: DropdownButtonFormField<T>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      style: TextStyle(fontSize: 12, color: WowColors.text),
      decoration: const InputDecoration(isDense: true),
      items: [
        DropdownMenuItem<T>(value: null, child: Text(label)),
        ...items,
      ],
      onChanged: onChanged,
    ),
  );
  String _watchLabel(WatchFilter f) => switch (f) {
    WatchFilter.all => '全部观看状态',
    WatchFilter.unwatched => '还没看过',
    WatchFilter.watching => '正在观看',
    WatchFilter.watched => '已经看过',
    WatchFilter.watchlist => '我的待看',
    WatchFilter.favorites => '我喜欢的',
  };
}

/// `3:45` for a track row; the music shelf shows length where films show a
/// watch-list bookmark.
String _clockText(double seconds) {
  final total = seconds.round();
  return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
}

class CollectionsView extends StatelessWidget {
  const CollectionsView({
    super.key,
    required this.store,
    required this.onOpen,
    required this.onAgent,
    required this.onWatchlist,
  });
  final LibraryStore store;
  final ValueChanged<FilmCollection> onOpen;
  final VoidCallback onAgent, onWatchlist;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) => ListView(
        padding: EdgeInsets.all(box.maxWidth < 700 ? 20 : 32),
        children: [
          PageIntro(
            action: FilledButton.icon(
              onPressed: onAgent,
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('让 Agent 挑选'),
            ),
          ),
          const SizedBox(height: 24),
          CinemaPanel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.bookmarks_outlined,
                color: WowColors.accent,
                size: 30,
              ),
              title: const Text('我的待看'),
              subtitle: Text(
                '${store.taste.watchlist.where((id) => store.items.any((i) => i.id == id)).length} 部影片 · 随时加入，慢慢看完',
              ),
              trailing: const Icon(Icons.arrow_forward),
              onTap: onWatchlist,
            ),
          ),
          const SizedBox(height: 24),
          if (store.collections.isEmpty)
            EmptyCinema(
              icon: Icons.playlist_play_rounded,
              title: '为每一种心情，留一份片单',
              description: '在片库中筛选并保存，或让 Agent 根据你此刻的想法挑选。片单只收录你片库中真实存在的影片。',
              action: OutlinedButton(
                onPressed: onAgent,
                child: const Text('创建第一份片单'),
              ),
            ),
          for (final c in store.collections)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: CinemaPanel(
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 78,
                      decoration: BoxDecoration(
                        color: WowColors.accent.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        Icons.playlist_play,
                        color: WowColors.accent,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: InkWell(
                        onTap: () => onOpen(c),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${c.itemIds.where((id) => store.items.any((i) => i.id == id)).length} 部可用影片',
                              style: TextStyle(
                                fontSize: 12,
                                color: WowColors.muted,
                              ),
                            ),
                            if (c.description.isNotEmpty)
                              Text(
                                c.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: WowColors.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: '打开片单',
                      onPressed: () => onOpen(c),
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '片单操作',
                      onSelected: (_) => store.removeCollection(c.id),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('删除片单（保留影片）'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
