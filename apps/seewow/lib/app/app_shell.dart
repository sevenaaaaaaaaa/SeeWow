import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent/agent_controller.dart';
import '../data/iptv_store.dart';
import '../data/library_store.dart';
import '../design/cinema_widgets.dart';
import '../design/tokens.dart';
import '../design/skin_surface.dart';
import '../domain/library_intelligence.dart';
import '../domain/media_item.dart';
import '../downloads/download_manager.dart';
import '../downloads/download_task.dart';
import '../downloads/downloads_view.dart';
import '../features/agent_view.dart';
import '../features/detail_view.dart';
import '../features/home_view.dart';
import '../features/library_view.dart';
import '../features/live_view.dart';
import '../features/settings_view.dart';
import '../features/sources_view.dart';
import '../playback/player_screen.dart';
import '../remote/remote_hub.dart';
import '../sources/source_scanner.dart';

enum Section {
  home,
  library,
  collections,
  sources,
  agent,
  live,
  settings,
  music,
}

const _destinations = [
  (Section.home, Icons.space_dashboard_outlined, '为你放映'),
  (Section.library, Icons.video_library_outlined, '媒体库'),
  (Section.collections, Icons.bookmarks_outlined, '我的片单'),
  (Section.sources, Icons.hub_outlined, '片源与订阅'),
  (Section.agent, Icons.auto_awesome_outlined, '影院 Agent'),
  (Section.live, Icons.sensors_rounded, '直播'),
  (Section.music, Icons.library_music_outlined, '音乐库'),
  (Section.settings, Icons.settings_outlined, '设置'),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, required this.iptv});
  final LibraryStore store;
  final IPTVStore iptv;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _ShellRemoteLibrary implements RemoteLibraryHost {
  _ShellRemoteLibrary(this.shell);
  final _AppShellState shell;

  @override
  Future<List<RemoteLibraryItem>> remoteItems() async => [
    for (final item in shell._store.items)
      RemoteLibraryItem(
        id: item.id,
        title: item.displayTitle,
        year: item.year ?? 0,
        kind: item.kind.name,
        duration: item.duration.round(),
      ),
  ];

  @override
  Future<bool> remoteOpen(String id) async {
    final matches = shell._store.items.where((item) => item.id == id);
    if (matches.isEmpty) return false;
    shell._play(matches.first);
    return true;
  }
}

class _AppShellState extends State<AppShell> {
  Section _section = Section.home;
  late AgentController _agent;
  FilmCollection? _collection;
  WatchFilter _watch = WatchFilter.all;
  MediaKind? _kind;
  String _query = '';
  int _libraryKey = 0;
  bool _playerOpen = false;
  late final LibraryStore _spaceStore;
  late final DownloadManager _downloads;
  bool _inSpace = false;
  LibraryStore get _store => _inSpace ? _spaceStore : widget.store;
  @override
  void initState() {
    super.initState();
    _spaceStore = LibraryStore(space: 2);
    final scanner = SourceScanner();
    _spaceStore.scanner = scanner.scan;
    _spaceStore
        .load()
        .then((_) async {
          await _spaceStore.hydrateCredentials(scanner.headersFor);
          if (mounted) setState(() {});
        })
        .catchError((Object error) {
          debugPrint('space library unavailable: $error');
        });
    _downloads = DownloadManager(
      resolver: (id) async {
        final item = _store.items.where((i) => i.id == id).firstOrNull;
        if (item == null) return null;
        final source = _store.sources
            .where((s) => s.id == item.sourceId)
            .firstOrNull;
        return ResolvedMedia(await scanner.prepare(item, source), source);
      },
    );
    _downloads.load().catchError((Object error) {
      debugPrint('downloads unavailable: $error');
    });
    RemoteHub.instance.library = _ShellRemoteLibrary(this);
    _agent = AgentController(_store);
    _agent.load().catchError((Object e) {
      debugPrint('Agent history unavailable');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  @override
  void dispose() {
    _agent.dispose();
    super.dispose();
  }

  void _select(Section s) => setState(() {
    _section = s;
    if (s == Section.library) {
      _collection = null;
      _watch = WatchFilter.all;
      _kind = null;
      _query = '';
      _libraryKey++;
    }
  });
  void _library({
    FilmCollection? collection,
    WatchFilter watch = WatchFilter.all,
    String query = '',
    MediaKind? kind,
  }) => setState(() {
    _section = Section.library;
    _collection = collection;
    _watch = watch;
    _query = query;
    _kind = kind;
    _libraryKey++;
  });
  void _run(String prompt) {
    _select(Section.agent);
    if (prompt.isNotEmpty) _agent.run(prompt);
  }

  void _toggleSpace() {
    setState(() {
      _inSpace = !_inSpace;
      _section = Section.home;
      _collection = null;
      _agent = AgentController(_store);
    });
    _agent.load().catchError((Object error) {
      debugPrint('Agent history unavailable');
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_inSpace ? '已进入解耦空间' : '已回到主空间'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _enterSpace() {
    if (!_inSpace) _toggleSpace();
  }

  void _open(MediaItem item) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DetailView(
        item: _store.current(item),
        store: _store,
        onPlay: _play,
        downloads: _downloads,
      ),
    ),
  );
  void _play(MediaItem item) => _playLive(_store.current(item), live: false);
  Future<void> _playLive(MediaItem item, {bool live = true}) async {
    if (_playerOpen) return;
    _playerOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PlayerScreen(
            item: item,
            isLive: live,
            resolve: live
                ? null
                : (i) async {
                    final offline = _downloads.pathFor(i.id);
                    if (offline != null) {
                      return i.copyWith(
                        locator: Uri.file(offline).toString(),
                        httpHeaders: const {},
                      );
                    }
                    return SourceScanner().prepare(
                      i,
                      _store.sources
                          .where((s) => s.id == i.sourceId)
                          .firstOrNull,
                    );
                  },
            onProgress: live
                ? null
                : (position, duration) {
                    _store.updatePosition(item, position, duration);
                  },
          ),
        ),
      );
    } finally {
      _playerOpen = false;
    }
  }

  Future<void> _playDownload(DownloadTask task) async {
    final item = _store.items.where((i) => i.id == task.itemId).firstOrNull;
    if (item == null) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('片库中已没有该条目，无法播放缓存')));
      }
      return;
    }
    _play(item);
  }

  void _launch() {
    if (!mounted) return;
    final launch = Platform.environment['SEEWOW_LAUNCH'];
    if (launch == 'movies' || launch == 'tv') {
      _library(kind: launch == 'movies' ? MediaKind.movie : MediaKind.episode);
      return;
    }
    final section = Section.values.where((s) => s.name == launch).firstOrNull;
    if (section != null) _select(section);
    if (launch == 'detail' && _store.items.isNotEmpty)
      _open(_store.movies.firstOrNull ?? _store.items.first);
    if (launch == 'play' && _store.items.isNotEmpty)
      _play(_store.movies.firstOrNull ?? _store.items.first);
    if (launch == 'playweb') {
      final i = _store.items
          .where((i) => i.locator.startsWith('http'))
          .firstOrNull;
      if (i != null) _play(i);
    }
    if (launch == 'liveplay' && widget.iptv.channels.isNotEmpty) {
      final c = widget.iptv.channels.first;
      _playLive(
        MediaItem(
          id: c.id,
          sourceId: c.playlistId,
          kind: MediaKind.other,
          title: c.name,
          locator: c.url,
        ),
      );
    }
  }

  Future<void> _search() async {
    final selection = await showDialog<Object>(
      context: context,
      builder: (_) => _CommandPalette(store: _store),
    );
    if (!mounted) return;
    if (selection is MediaItem) _open(selection);
    if (selection is Section) _select(selection);
    if (selection is String) _library(query: selection);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, _spaceStore, _agent]),
    builder: (context, _) {
      final width = MediaQuery.sizeOf(context).width;
      final sidebar = width >= 1180;
      final rail = width >= 760 && !sidebar;
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _search,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true):
              _search,
        },
        child: Scaffold(
          backgroundColor: WowColors.ink,
          body: SkinCanvas(
            child: SafeArea(
              child: Row(
                children: [
                  if (sidebar || rail) _navigation(rail),
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          height: 68,
                          padding: EdgeInsets.symmetric(
                            horizontal: width < 760 ? 16 : 32,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: WowColors.line),
                            ),
                          ),
                          child: Row(
                            children: [
                              if (width >= 760) ...[
                                Text(
                                  _destinations
                                      .firstWhere((d) => d.$1 == _section)
                                      .$3,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: WowColors.muted,
                                  ),
                                ),
                                const SizedBox(width: 24),
                              ],
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 390,
                                    ),
                                    child: OutlinedButton(
                                      onPressed: _search,
                                      style: OutlinedButton.styleFrom(
                                        alignment: Alignment.centerLeft,
                                        backgroundColor: WowColors.panel,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 13,
                                        ),
                                        side: BorderSide(color: WowColors.line),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.search,
                                            size: 17,
                                            color: WowColors.muted,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              '搜索你的影院',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: WowColors.muted,
                                              ),
                                            ),
                                          ),
                                          if (width >= 760)
                                            Text(
                                              Platform.isMacOS
                                                  ? '⌘ K'
                                                  : 'Ctrl K',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: WowColors.muted,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ActionChip(
                                avatar: Icon(
                                  _inSpace
                                      ? Icons.layers_rounded
                                      : Icons.home_work_outlined,
                                  size: 14,
                                ),
                                label: Text(
                                  _inSpace ? '解耦空间' : '主空间',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onPressed: _toggleSpace,
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: '刷新片库',
                                onPressed: _store.scanning
                                    ? null
                                    : () async {
                                        await _store.refreshAll();
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text('片库已刷新'),
                                                duration: Duration(seconds: 1),
                                              ),
                                            );
                                      },
                                icon: _store.scanning
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.refresh, size: 19),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: '我的待看',
                                onPressed: () =>
                                    _library(watch: WatchFilter.watchlist),
                                icon: const Icon(
                                  Icons.bookmark_border,
                                  size: 19,
                                ),
                              ),
                              if (width >= 760) ...[
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => _select(Section.sources),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('连接片源'),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_inSpace)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 6,
                            ),
                            color: WowColors.panel,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.layers_outlined,
                                  size: 15,
                                  color: WowColors.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '解耦空间 · 独立文件夹与片库，与主空间互不影响',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: WowColors.muted,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _toggleSpace,
                                  child: const Text('返回主空间'),
                                ),
                              ],
                            ),
                          ),
                        if (_store.scanning)
                          const LinearProgressIndicator(minHeight: 2),
                        Expanded(child: _content()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: width >= 760
              ? null
              : NavigationBar(
                  height: 68,
                  selectedIndex:
                      _section == Section.collections ||
                          _section == Section.live ||
                          _section == Section.music
                      ? 4
                      : [
                          Section.home,
                          Section.library,
                          Section.agent,
                          Section.sources,
                          Section.settings,
                        ].indexOf(_section).clamp(0, 4),
                  onDestinationSelected: (n) => _select(
                    [
                      Section.home,
                      Section.library,
                      Section.agent,
                      Section.sources,
                      Section.settings,
                    ][n],
                  ),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      label: '放映',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.video_library_outlined),
                      label: '片库',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.auto_awesome_outlined),
                      label: 'Agent',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.hub_outlined),
                      label: '片源',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.more_horiz),
                      label: '更多',
                    ),
                  ],
                ),
        ),
      );
    },
  );
  Widget _navigation(bool rail) => SizedBox(
    width: rail ? 76 : 210,
    child: SkinSurface(
      radius: 0,
      color: WowColors.shell,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(rail ? 20 : 24, 26, 16, 30),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: WowColors.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: WowColors.onAccent,
                    size: 24,
                  ),
                ),
                if (!rail) ...[
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'SeeWow',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.8,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!rail)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 14),
              child: Text(
                '我的私人影院',
                style: TextStyle(fontSize: 11, color: WowColors.muted),
              ),
            ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: rail ? 12 : 14),
              children: [
                for (final d in _destinations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Tooltip(
                      message: rail ? d.$3 : '',
                      child: Material(
                        color: _section == d.$1
                            ? WowColors.accent.withValues(alpha: .11)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _select(d.$1),
                          child: SizedBox(
                            height: 46,
                            child: Row(
                              mainAxisAlignment: rail
                                  ? MainAxisAlignment.center
                                  : MainAxisAlignment.start,
                              children: [
                                if (!rail) const SizedBox(width: 12),
                                Icon(
                                  d.$2,
                                  size: 19,
                                  color: _section == d.$1
                                      ? WowColors.accent
                                      : WowColors.muted,
                                ),
                                if (!rail) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    d.$3,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: _section == d.$1
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: _section == d.$1
                                          ? WowColors.accent
                                          : WowColors.muted,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (d.$1 == Section.agent && _agent.busy)
                                    const SizedBox(
                                      width: 10,
                                      height: 10,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                      ),
                                    ),
                                  const SizedBox(width: 12),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!rail)
            Padding(
              padding: const EdgeInsets.all(18),
              child: CinemaPanel(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('LIBRARY STATUS'),
                    const SizedBox(height: 12),
                    Text(
                      '${_store.items.length} 部影片已入库',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 6,
                          color: _store.sourceErrors.isEmpty
                              ? WowColors.success
                              : WowColors.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _store.scanning
                                ? '正在同步片源'
                                : _store.sourceErrors.isEmpty
                                ? '${_store.sources.length} 个来源已添加'
                                : '${_store.sourceErrors.length} 个来源需要检查',
                            style: TextStyle(
                              fontSize: 10,
                              color: WowColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'CINEMA, MADE PERSONAL.',
                      style: TextStyle(
                        fontSize: 7,
                        letterSpacing: 1.2,
                        color: WowColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (rail) const SizedBox(height: 20),
        ],
      ),
    ),
  );
  Widget _content() => switch (_section) {
    Section.music => LibraryView(
      key: const ValueKey('music'),
      store: _store,
      onOpen: _open,
      initialKind: MediaKind.audio,
      onSources: () => _select(Section.sources),
    ),
    Section.home => HomeView(
      store: _store,
      onOpen: _open,
      onPlay: _play,
      onAgent: _run,
      onSources: () => _select(Section.sources),
      onLibrary: () => _library(),
      onLongPull: _inSpace ? null : _enterSpace,
    ),
    Section.library => LibraryView(
      key: ValueKey(_libraryKey),
      store: _store,
      onOpen: _open,
      initialText: _query,
      initialKind: _kind,
      initialWatch: _watch,
      collection: _collection,
      onSources: () => _select(Section.sources),
    ),
    Section.collections => CollectionsView(
      store: _store,
      onOpen: (c) => _library(collection: c),
      onAgent: () => _run('按我的口味生成片单'),
      onWatchlist: () => _library(watch: WatchFilter.watchlist),
    ),
    Section.sources => SourcesView(
      store: _store,
      iptv: widget.iptv,
      onAgent: _run,
    ),
    Section.agent => AgentView(agent: _agent, iptv: widget.iptv, onOpen: _open),
    Section.live => LiveView(store: widget.iptv, onPlay: _playLive),
    Section.settings => Column(
      children: [
        if (MediaQuery.sizeOf(context).width < 760)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 10,
              children: [
                OutlinedButton(
                  onPressed: () => _select(Section.collections),
                  child: const Text('我的片单'),
                ),
                OutlinedButton(
                  onPressed: () => _select(Section.live),
                  child: const Text('直播'),
                ),
                OutlinedButton(
                  onPressed: () => _select(Section.music),
                  child: const Text('音乐库'),
                ),
              ],
            ),
          ),
        Expanded(
          child: SettingsView(
            agent: _agent,
            store: _store,
            downloads: _downloads,
            onOpenDownloads: () => showDownloads(
              context,
              manager: _downloads,
              onPlay: _playDownload,
            ),
            onConfigureAgent: () => configureAgent(context, _agent),
            onSources: () => _select(Section.sources),
          ),
        ),
      ],
    ),
  };
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.store});
  final LibraryStore store;
  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _text = TextEditingController();
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = LibraryQuery(text: _text.text)
        .apply(widget.store.items, widget.store.taste)
        .take(8)
        .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                controller: _text,
                onChanged: (_) => setState(() {}),
                onSubmitted: (v) => Navigator.pop(context, v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索影片、年份、类型，或跳转到功能',
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    if (_text.text.isEmpty) ...[
                      for (final d in _destinations)
                        ListTile(
                          dense: true,
                          leading: Icon(d.$2, size: 18),
                          title: Text(
                            d.$3,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: const Icon(
                            Icons.subdirectory_arrow_left,
                            size: 16,
                          ),
                          onTap: () => Navigator.pop(context, d.$1),
                        ),
                    ] else ...[
                      for (final i in items)
                        ListTile(
                          leading: const Icon(Icons.movie_outlined, size: 18),
                          title: Text(
                            i.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${i.year ?? '年份未知'} · ${widget.store.sources.where((s) => s.id == i.sourceId).firstOrNull?.name ?? '未知来源'} · ${i.genres.join(' / ')}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          onTap: () => Navigator.pop(context, i),
                        ),
                      ListTile(
                        leading: const Icon(Icons.search, size: 18),
                        title: const Text(
                          '在媒体库中查看全部结果',
                          style: TextStyle(fontSize: 13),
                        ),
                        onTap: () => Navigator.pop(context, _text.text),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
