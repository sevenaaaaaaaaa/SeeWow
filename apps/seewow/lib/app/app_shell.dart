import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:window_manager/window_manager.dart';

import '../agent/agent_controller.dart';
import 'shake_refresh.dart';
import '../data/iptv_store.dart';
import '../data/online_source_store.dart';
import '../data/library_store.dart';
import '../design/brand_mark.dart';
import '../design/cinema_widgets.dart';
import '../design/liquid_glass.dart';
import '../design/liquid_nav.dart';
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
import '../features/frame_bookmarks_view.dart';
import '../features/library_view.dart';
import '../features/live_view.dart';
import '../features/settings_view.dart';
import '../features/short_drama_view.dart';
import '../features/online_source_view.dart';
import '../features/sources_view.dart';
import '../playback/frame_bookmarks.dart';
import '../playback/player_screen.dart';
import '../remote/remote_hub.dart';
import '../remote/remote_server.dart';
import '../sources/public_domain_library.dart';
import '../sources/source_scanner.dart';

enum Section {
  home,
  shortDramas,
  library,
  collections,
  sources,
  agent,
  live,
  online,
  settings,
  music,
}

const _destinations = [
  (Section.home, Icons.space_dashboard_outlined, '为你放映'),
  (Section.shortDramas, Icons.movie_filter_outlined, '短剧'),
  (Section.library, Icons.video_library_outlined, '媒体库'),
  (Section.collections, Icons.bookmarks_outlined, '我的片单'),
  (Section.sources, Icons.hub_outlined, '片源与订阅'),
  (Section.agent, Icons.auto_awesome_outlined, '影院 Agent'),
  (Section.live, Icons.sensors_rounded, '直播'),
  (Section.online, Icons.travel_explore_rounded, '在线源'),
  (Section.music, Icons.library_music_outlined, '音乐库'),
  (Section.settings, Icons.settings_outlined, '设置'),
];

/// A group heading inside a glass sheet.
class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
    child: Text(text, style: WowType.monoLabel(9.5, spacing: 1.6)),
  );
}

/// What the fifth seat shows while it stands for a section.
const _overflowMeta =
    <Section, ({String label, IconData icon, IconData active})>{
      Section.sources: (
        label: '片源',
        icon: Icons.hub_outlined,
        active: Icons.hub_rounded,
      ),
      Section.shortDramas: (
        label: '短剧',
        icon: Icons.movie_filter_outlined,
        active: Icons.movie_filter,
      ),
      Section.collections: (
        label: '片单',
        icon: Icons.bookmarks_outlined,
        active: Icons.bookmarks,
      ),
      Section.live: (
        label: '直播',
        icon: Icons.sensors_rounded,
        active: Icons.sensors,
      ),
      Section.music: (
        label: '音乐',
        icon: Icons.library_music_outlined,
        active: Icons.library_music,
      ),
      Section.settings: (
        label: '设置',
        icon: Icons.settings_outlined,
        active: Icons.settings,
      ),
    };

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.store,
    required this.iptv,
    required this.online,
  });
  final LibraryStore store;
  final IPTVStore iptv;
  final OnlineSourceStore online;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _ShellBridgeHost implements RemoteBridgeHost {
  _ShellBridgeHost(this.shell);
  final _AppShellState shell;

  @override
  List<MediaItem> get bridgeItems => shell._store.items;

  @override
  Future<MediaItem?> bridgeItem(String id) async =>
      shell._store.items.where((item) => item.id == id).firstOrNull;

  @override
  Future<MediaItem> bridgePrepare(MediaItem item) => SourceScanner().prepare(
    item,
    shell._store.sources.where((s) => s.id == item.sourceId).firstOrNull,
  );
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

  late final RefreshGestureGate _shakeGate;
  late final ShakeRefreshController _shaker;
  StreamSubscription<AccelerometerEvent>? _accel;
  _WindowShakeListener? _windowShake;
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
    RemoteServer.instance.bridgeHost = _ShellBridgeHost(this);
    _agent = AgentController(_store);
    _agent.load().catchError((Object e) {
      debugPrint('Agent history unavailable');
    });
    _wireShake();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
  }

  /// Shake-to-refresh: a real accelerometer on phones, a shaken window on the
  /// desktop, and no gesture at all where neither exists.
  void _wireShake() {
    _shakeGate = RefreshGestureGate();
    // Widget tests must never open a real sensor or window listener: the
    // platform implementation installs timers that keep pumpAndSettle waiting.
    final underTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (underTest) {
      _shaker = ShakeRefreshController(
        gate: _shakeGate,
        onRefresh: _shakeRefresh,
      );
      return;
    }
    final surface = shakeSurfaceFor(
      isMobile: Platform.isAndroid || Platform.isIOS,
      isDesktop: Platform.isMacOS || Platform.isWindows || Platform.isLinux,
      sensorsAvailable: Platform.isAndroid || Platform.isIOS,
    );
    _shaker = ShakeRefreshController(
      gate: _shakeGate,
      detector: ReversalShakeDetector(
        // Pixels for a window drag, m/s² for a phone.
        minAmplitude: surface == ShakeSurface.window ? 48 : 14,
      ),
      onRefresh: _shakeRefresh,
    );
    if (surface == ShakeSurface.accelerometer) {
      // 20 ms sampling: the detector needs four or five samples inside
      // 1.1 s, and the package default (200 ms) only provides five.
      _accel = accelerometerEventStream(
        samplingPeriod: SensorInterval.gameInterval,
      ).listen((event) {
        _shaker.feed(event.x, DateTime.now());
      });
    } else if (surface == ShakeSurface.window) {
      final listener = _WindowShakeListener(
        (x, at) => _shaker.feed(x, at),
      );
      windowManager.addListener(listener);
      _windowShake = listener;
    }
  }

  /// Loads the bundled public-domain titles so a new install has something to
  /// play before any source is configured.
  Future<void> _loadSamples() async {
    final added = await _store.addItems(buildPublicDomainItems());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added == 0 ? '示例片库已经载入过了' : '已载入 $added 部免版权影片',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
    setState(() {});
  }

  Future<void> _shakeRefresh() async {
    if (!mounted) return;
    await _store.refreshAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('片库已刷新'), duration: Duration(seconds: 1)),
    );
  }

  @override
  void dispose() {
    _accel?.cancel();
    if (_windowShake != null) windowManager.removeListener(_windowShake!);
    _shaker.dispose();
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

  /// The overflow shelf.
  ///
  /// Two groups, because the old sheet mixed "places to go" with "things to
  /// change" in one flat list: 浏览 takes the four content destinations, 设置
  /// stands alone. Choosing anything here also teaches the fifth seat which
  /// section it now stands for.
  Future<void> _showMore() async {
    final phone = MediaQuery.sizeOf(context).width < 620;
    final choice = await showGlassSheet<Object>(
      context: context,
      builder: (sheet) => GlassSheet(
        title: '更多',
        subtitle: '导航上留了四个常去处，其余都在这里',
        children: [
          const _SheetLabel('浏览'),
          _sheetEntry(sheet, Section.shortDramas),
          _sheetEntry(sheet, Section.collections),
          _sheetEntry(sheet, Section.live),
          _sheetEntry(sheet, Section.music),
          const _SheetLabel('管理'),
          _sheetEntry(sheet, Section.settings),
          // A phone header cannot hold nine controls, so the two it dropped
          // live here rather than disappearing.
          if (phone) ...[
            const SizedBox(height: 6),
            _sheetAction(sheet, 'refresh', '刷新片库', Icons.refresh),
            _sheetAction(
              sheet,
              'space',
              _inSpace ? '回到主空间' : '进入解耦空间',
              Icons.layers_outlined,
            ),
          ],
        ],
      ),
    );
    if (!mounted) return;
    if (choice is Section) {
      setState(() => _overflowSeat = choice);
      _select(choice);
    } else if (choice == 'refresh') {
      await _refreshLibrary();
    } else if (choice == 'space') {
      _toggleSpace();
    }
  }

  Widget _sheetAction(
    BuildContext sheet,
    String key,
    String label,
    IconData icon,
  ) {
    return PressableLens(
      radius: 16,
      semanticLabel: label,
      onTap: () => Navigator.pop(sheet, key),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(icon, size: 18, color: WowColors.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: WowType.body(14))),
            Icon(Icons.chevron_right, size: 16, color: WowColors.faint),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  /// One refresh path for the header button and the sheet row.
  Future<void> _refreshLibrary() async {
    await _store.refreshAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('片库已刷新'), duration: Duration(seconds: 1)),
    );
  }

  Widget _sheetEntry(BuildContext sheet, Section s, {String? hint}) {
    final meta = _overflowMeta[s]!;
    final label = _destinations.firstWhere((d) => d.$1 == s).$3;
    return PressableLens(
      radius: 16,
      semanticLabel: label,
      onTap: () => Navigator.pop(sheet, s),
      child: SizedBox(
        height: 50,
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(meta.icon, size: 18, color: WowColors.muted),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: WowType.body(14))),
            if (hint != null) ...[
              Text(hint, style: WowType.monoLabel(9.5)),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, size: 16, color: WowColors.faint),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  void _open(MediaItem item) => Navigator.of(context).push(
    GlassPageRoute<void>(
      builder: (_) => DetailView(
        item: _store.current(item),
        store: _store,
        onPlay: _play,
        downloads: _downloads,
      ),
    ),
  );
  void _play(MediaItem item) => _playLive(_store.current(item), live: false);

  /// Opens one saved frame: finds the film it came from and starts there.
  /// 影片已经不在片库里时不假装能播，直接说清楚。
  void _openFrame(FrameBookmark frame) {
    for (final item in _store.items) {
      if (item.id == frame.itemId) {
        _playLive(_store.current(item), live: false, startAt: frame.seconds);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('这张精彩帧所属的影片已不在片库')),
    );
  }

  Future<void> _openFrames() =>
      showFrameBookmarks(context, onOpen: _openFrame);
  /// Plays a short-drama queue from [index] and rolls on to the next episode
  /// when the current one ends.
  void _playDramaQueue(List<MediaItem> queue, int index) {
    if (queue.isEmpty || index >= queue.length) return;
    _playLive(queue[index], live: false, queue: queue, index: index);
  }

  Future<void> _playLive(
    MediaItem item, {
    bool live = true,
    List<MediaItem>? queue,
    int index = 0,
    double? startAt,
  }) async {
    if (_playerOpen) return;
    _playerOpen = true;
    _shakeGate.playing = true;
    var advanced = false;
    try {
      final result = await Navigator.of(context).push<bool>(
        GlassPageRoute<bool>(
          builder: (_) => PlayerScreen(
            item: item,
            startAt: startAt,
            isLive: live,
            resolve: live
                ? null
                : (i) async {
                    if (Uri.tryParse(i.locator)?.scheme == 'file') return i;
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
            // The player closes itself and reports `true`; anything else
            // (a user who pressed back, a sheet on top) must not roll on.
            onCompleted: queue == null || index + 1 >= queue.length
                ? null
                : () => advanced = true,
          ),
        ),
      );
      if (result != true) advanced = false;
    } finally {
      // 进度默认 20 秒节流落盘；关掉播放器时补写一次，退出应用也不丢。
      await _store.flushProgress();
      _playerOpen = false;
      _shakeGate.playing = false;
      _shakeGate.markInteraction();
      if (mounted && advanced && queue != null && index + 1 < queue.length) {
        unawaited(
          _playLive(
            queue[index + 1],
            live: false,
            queue: queue,
            index: index + 1,
          ),
        );
      }
    }
  }

  Future<void> _playDownload(DownloadTask task) async {
    final file = task.filePath;
    if (file == null || !File(file).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('缓存文件已不在，请重新缓存；不会回落到联网播放')),
        );
      }
      return;
    }
    final item = _store.items.where((i) => i.id == task.itemId).firstOrNull;
    final local = (item ??
            MediaItem(
              id: task.itemId,
              sourceId: task.sourceId,
              kind: MediaKind.movie,
              title: task.title,
              locator: Uri.file(file).toString(),
            ))
        .copyWith(locator: Uri.file(file).toString(), httpHeaders: const {});
    // Straight to the player: going through _play() would re-read the library
    // copy and hand the remote locator to the decoder.
    unawaited(_playLive(local, live: false));
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
    if (launch == 'detail' && _store.items.isNotEmpty) {
      _open(_store.movies.firstOrNull ?? _store.items.first);
    }
    if (launch == 'play' && _store.items.isNotEmpty) {
      _play(_store.movies.firstOrNull ?? _store.items.first);
    }
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

  /// ⌘K opens search; ⌘1…⌘5 stand on a seat.
  ///
  /// The five seat shortcuts live here rather than in the tab bar so they work
  /// from any screen, and they route through [_navSelect], which means the
  /// overflow seat behaves exactly like a tap.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final map = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _search,
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): _search,
    };
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
    ];
    for (var i = 0; i < digits.length; i++) {
      final seat = i;
      map[SingleActivator(digits[i], meta: true)] = () => _navSelect(seat);
      map[SingleActivator(digits[i], control: true)] = () => _navSelect(seat);
    }
    return map;
  }

  /// One entry point for the cache page, so the empty state can send the user
  /// to the library instead of straight back to where they came from.
  Future<void> _openDownloads() async {
    await showDownloads(
      context,
      manager: _downloads,
      onPlay: _playDownload,
      onBrowse: () {
        Navigator.of(context).maybePop();
        _library();
      },
    );
  }

  Future<void> _search() async {
    final selection = await showDialog<Object>(
      context: context,
      builder: (_) => _CommandPalette(store: _store, commands: _paletteCommands),
    );
    if (!mounted) return;
    if (selection is MediaItem) _open(selection);
    if (selection is Section) _select(selection);
    if (selection is _PaletteCommand) {
      await selection.run(context);
      return;
    }
    if (selection is String) _library(query: selection);
  }

  /// Settings that live in a dialog, plus the cache page, offered where the
  /// user already is. No destination is invented: each entry opens the dialog
  /// the settings page opens.
  List<_PaletteCommand> get _paletteCommands => [
    _PaletteCommand(
      label: '离线缓存',
      icon: Icons.download_for_offline_outlined,
      run: (_) async => _openDownloads(),
    ),
    for (final c in wowSettingsCommands())
      _PaletteCommand(
        label: c.label,
        icon: c.icon,
        run: (context) async => c.open(context),
      ),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // `online` 也要听：首页与「片源」页上的「内置 N 个站点」是异步铺完才有数的。
    listenable: Listenable.merge([
      widget.store,
      _spaceStore,
      _agent,
      widget.online,
    ]),
    builder: (context, _) {
      final width = MediaQuery.sizeOf(context).width;
      final sidebar = width >= 1180;
      final rail = width >= 760 && !sidebar;
      return CallbackShortcuts(
        bindings: _shortcuts,
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
                              // The section name used to appear only from
                              // 760 px up — exactly the width where the user
                              // least needs it. On a phone the header has room
                              // for a title and one icon; that is what it shows.
                              Text(
                                _destinations
                                    .firstWhere((d) => d.$1 == _section)
                                    .$3,
                                style: WowType.display(
                                  width < 620 ? 18 : 20,
                                  FontWeight.w500,
                                  spacing: -.5,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(width: 18),
                              if (width >= 620)
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        maxWidth: 390,
                                      ),
                                      child: PressableLens(
                                        radius: 99,
                                        onTap: _search,
                                        semanticLabel: '搜索你的影院',
                                        child: LiquidGlass(
                                          radius: 99,
                                          edge: .26,
                                          lifted: false,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
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
                                                  style: WowType.body(
                                                    12.5,
                                                    color: WowColors.muted,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                Platform.isMacOS
                                                    ? '⌘K'
                                                    : 'Ctrl K',
                                                style: WowType.monoLabel(9.5),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                const Spacer(),
                              if (width < 620)
                                IconButton(
                                  tooltip: '搜索（⌘K）',
                                  onPressed: _search,
                                  icon: const Icon(Icons.search, size: 19),
                                ),
                              // 片源与订阅是配置，不是内容，不再占一个导航席。
                              // 窄屏在这里给常驻入口；宽屏右侧本来就有「连接片源」。
                              // 站在片源页时这个入口就是「再点一次同一个地方」，
                              // 于是它自己收起来。
                              if (width < 760 && _section != Section.sources)
                                IconButton(
                                  tooltip: '片源与订阅',
                                  onPressed: () => _select(Section.sources),
                                  // 375 px 宽上顶栏一行只剩 2 px：新入口自己收窄，
                                  // 不去挤标题，也不去动别的按钮。
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(
                                    Icons.hub_outlined,
                                    size: 19,
                                  ),
                                ),
                              // 窄屏「设置」原本只藏在第五席的「更多」弹层里：
                              // 要先站到某个溢出分区，再点一次同一个座位。用户找不到，
                              // 就是没有。760 以下没有侧栏，这里给它一个常驻入口。
                              if (width < 760)
                                IconButton(
                                  tooltip: '设置',
                                  onPressed: () => _select(Section.settings),
                                  icon: const Icon(
                                    Icons.settings_outlined,
                                    size: 19,
                                  ),
                                ),
                              const SizedBox(width: 10),
                              if (width >= 620)
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
                              // Refresh and the space switch move into the
                              // overflow sheet on a phone: the header had 9 px
                              // more than a 375 px screen could hold, and two
                              // rarely used controls are the right thing to
                              // give up, not the section title or search.
                              if (width >= 620) ...[
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: '刷新片库',
                                  onPressed: _store.scanning
                                      ? null
                                      : _refreshLibrary,
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
                              ],
                              const SizedBox(width: 4),
                              ListenableBuilder(
                                listenable: _downloads,
                                builder: (context, _) {
                                  final active = _downloads.activeCount;
                                  return IconButton(
                                    tooltip: '离线缓存',
                                    onPressed: () => _openDownloads(),
                                    icon: active > 0
                                        ? Badge.count(
                                            count: active,
                                            child: Icon(
                                              Icons.downloading,
                                              size: 19,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.download_for_offline_outlined,
                                            size: 19,
                                          ),
                                  );
                                },
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
                            padding: EdgeInsets.symmetric(
                              horizontal: width < 760 ? 16 : 32,
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
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 300),
                            switchInCurve: WowMotion.page,
                            switchOutCurve: Curves.easeOutCubic,
                            layoutBuilder: (current, previous) => Stack(
                              fit: StackFit.expand,
                              children: [
                                ...previous,
                                ?current,
                              ],
                            ),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, .014),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: KeyedSubtree(
                              key: ValueKey(_section),
                              child: _content(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: width >= 760 ? null : _liquidNav(),
        ),
      );
    },
  );
  /// The bar tracks the current section; the last four destinations share one
  /// seat.
  int get _navIndex => switch (_section) {
    Section.home => 0,
    Section.library => 1,
    Section.agent => 2,
    Section.online => 3,
    _ => 4,
  };

  /// The seat stands for a section instead of for the word 更多.
  ///
  /// A tab that always reads 更多 hides four destinations behind a tap and
  /// still tells the user nothing about where they lead. Remembering the last
  /// one costs nothing, shows the destination in the bar, and keeps the seat's
  /// icon and label meaningful while the user is standing on it.
  /// 第五席默认站「短剧」。
  ///
  /// 内置源包随包发，但入口原本落在「更多」弹层里：只要用户不点两次，界面
  /// 和一个空应用没有区别——这就是「在线源」现在占第 4 席常驻的原因。
  /// 片源与订阅是配置而不是内容，已从导航撤出，改由顶栏进入；它仍记在
  /// 溢出表里，好让站在该页时第五席显示「片源」而不是一个无关的分区。
  Section _overflowSeat = Section.shortDramas;

  bool _isOverflow(Section s) => _overflowMeta.containsKey(s);

  void _navSelect(int n) {
    if (n == 4) {
      if (_isOverflow(_section)) {
        _showMore();
      } else {
        _select(_overflowSeat);
      }
      return;
    }
    _select(
      const [Section.home, Section.library, Section.agent, Section.online][n],
    );
  }

  Widget _liquidNav() => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 6),
    child: LiquidTabBar(
      tabs: [

        LiquidTab(
          label: '放映',
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
        ),
        LiquidTab(
          label: '片库',
          icon: Icons.video_library_outlined,
          activeIcon: Icons.video_library_rounded,
        ),
        LiquidTab(
          label: 'Agent',
          icon: Icons.auto_awesome_outlined,
          activeIcon: Icons.auto_awesome,
        ),
        LiquidTab(
          label: '在线源',
          icon: Icons.travel_explore_outlined,
          activeIcon: Icons.travel_explore_rounded,
        ),
        // 第五席站着谁：站在一个溢出分区上就写它自己的名字，否则写上次
        // 记住的那个。这样从顶栏进片源时，座位显示「片源」而不是「短剧」。
        LiquidTab(
          label:
              _overflowMeta[_section]?.label ?? _overflowMeta[_overflowSeat]!.label,
          icon:
              _overflowMeta[_section]?.icon ?? _overflowMeta[_overflowSeat]!.icon,
          activeIcon:
              _overflowMeta[_section]?.active ??
              _overflowMeta[_overflowSeat]!.active,
        ),
      ],
      index: _navIndex,
      onSelect: _navSelect,
    ),
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
                // The app icon and the sidebar now show the same mark: a
                // play shard cut from glass. An accent square with a play
                // glyph in it is what every media app already has.
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: WowColors.accent,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Center(
                    child: WowMark(
                      size: 27,
                      monochrome: true,
                      color: WowColors.onAccent,
                    ),
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
    Section.shortDramas => ShortDramaView(
      store: _store,
      onPlayQueue: _playDramaQueue,
      onSources: () => _select(Section.sources),
      onOnline: () => _select(Section.online),
    ),
    Section.music => LibraryView(
      key: const ValueKey('music'),
      store: _store,
      onOpen: _open,
      onPlay: _play,
      initialKind: MediaKind.audio,
      onSources: () => _select(Section.sources),
      onInteract: _shakeGate.markInteraction,
      downloads: _downloads,
    ),
    Section.home => HomeView(
      store: _store,
      onOpen: _open,
      onPlay: _play,
      onAgent: _run,
      onSources: () => _select(Section.sources),
      onOnline: () => _select(Section.online),
      onlineSites: widget.online.enabledSites.length,
      onLibrary: () => _library(),
      onLongPull: _inSpace ? null : _enterSpace,
      onInteract: _shakeGate.markInteraction,
      onSamples: _loadSamples,
    ),
    Section.library => LibraryView(
      key: ValueKey(_libraryKey),
      store: _store,
      onOpen: _open,
      onPlay: _play,
      initialText: _query,
      initialKind: _kind,
      initialWatch: _watch,
      collection: _collection,
      onSources: () => _select(Section.sources),
      onInteract: _shakeGate.markInteraction,
      downloads: _downloads,
      onFrames: _openFrames,
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
      onOnline: () => _select(Section.online),
      onlineSites: widget.online.enabledSites.length,
    ),
    Section.agent => AgentView(agent: _agent, iptv: widget.iptv, onOpen: _open),
    Section.live => LiveView(store: widget.iptv, onPlay: _playLive),
    Section.online => OnlineSourceView(
      store: widget.online,
      iptv: widget.iptv,
      localItems: _store.items,
      onPlay: (item, {live = false}) => _playLive(item, live: live),
    ),
    Section.settings => SettingsView(
      agent: _agent,
      store: _store,
      downloads: _downloads,
      onOpenDownloads: _openDownloads,
      onConfigureAgent: () => configureAgent(context, _agent),
      onSources: () => _select(Section.sources),
      onOpenFrame: _openFrame,
    ),
  };
}

/// One action offered by the palette.
class _PaletteCommand {
  const _PaletteCommand({
    required this.label,
    required this.icon,
    required this.run,
  });
  final String label;
  final IconData icon;
  final Future<void> Function(BuildContext) run;
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.store, required this.commands});
  final LibraryStore store;
  final List<_PaletteCommand> commands;
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
                      const Divider(height: 18),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                        child: Text(
                          '设置',
                          style: WowType.monoLabel(9, spacing: 1.4),
                        ),
                      ),
                      for (final c in widget.commands)
                        ListTile(
                          dense: true,
                          leading: Icon(c.icon, size: 18),
                          title: Text(
                            c.label,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: const Icon(Icons.tune, size: 15),
                          onTap: () => Navigator.pop(context, c),
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

/// Turn window drags into a sample stream. `onWindowMove` can fire faster than
/// `getPosition` resolves, so a read in flight suppresses the next one.
class _WindowShakeListener extends WindowListener {
  _WindowShakeListener(this.onSample);

  final void Function(double x, DateTime at) onSample;
  bool _reading = false;

  @override
  void onWindowMove() {
    if (_reading) return;
    _reading = true;
    _read();
  }

  Future<void> _read() async {
    try {
      final position = await windowManager.getPosition();
      onSample(position.dx, DateTime.now());
    } catch (error) {
      debugPrint('window shake sample failed: $error');
    } finally {
      _reading = false;
    }
  }
}
