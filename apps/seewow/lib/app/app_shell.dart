import 'dart:io';

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/iptv_store.dart';
import '../data/library_store.dart';
import '../design/atmosphere.dart';
import '../design/poster_tile.dart';
import '../design/entrance.dart';
import '../design/pressable.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../playback/player_screen.dart';
import '../features/detail_view.dart';
import '../features/home_view.dart';
import '../features/live_view.dart';
import '../features/settings_view.dart';

enum Section { home, movies, tv, live, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, required this.iptv});
  final LibraryStore store;
  final IPTVStore iptv;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  Section _section = Section.home;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyLaunchEnv());
  }

  /// Debug/QA hook: SEEWOW_LAUNCH=movies|tv|live|settings|detail|play opens a
  /// screen directly so screenshots and smoke runs are deterministic.
  Future<void> _applyLaunchEnv() async {
    final launch = Platform.environment['SEEWOW_LAUNCH'] ?? '';
    if (launch.isEmpty) return;
    if (launch == 'liveplay') {
      setState(() => _section = Section.live);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (widget.iptv.channels.isEmpty || !mounted) return;
      final c = widget.iptv.channels.first;
      _playLive(MediaItem(
        id: c.id,
        sourceId: c.playlistId,
        kind: MediaKind.other,
        title: c.name,
        locator: c.url,
        posterUrl: c.logo.isEmpty ? null : c.logo,
        quality: 'LIVE',
      ));
      return;
    }
    if (launch == 'movies' || launch == 'tv' || launch == 'live' || launch == 'settings') {
      final section = Section.values.firstWhere((s) => s.name == launch, orElse: () => Section.home);
      setState(() => _section = section);
      return;
    }
    final items = widget.store.items;
    if (items.isEmpty) return;
    if (launch == 'playweb') {
      final web = items.where((i) => i.locator.startsWith('http')).toList();
      if (web.isEmpty) return;
      _play(web.firstWhere((i) => i.kind == MediaKind.movie, orElse: () => web.first));
      return;
    }
    MediaItem? pick;
    for (final item in items) {
      if (item.kind == MediaKind.movie) { pick = item; break; }
    }
    pick ??= items.first;
    if (launch == 'detail') {
      _open(pick);
    } else if (launch == 'play') {
      _play(pick);
    }
  }

  void _open(MediaItem item) {
    Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, animation, __) => FadeTransition(
        opacity: animation,
        child: DetailView(item: item, store: widget.store, onPlay: _play),
      ),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: WowMotion.page, reverseCurve: Curves.easeIn);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: Tween(begin: const Offset(0, 0.035), end: Offset.zero).animate(curved), child: child),
        );
      },
    ));
  }

  void _play(MediaItem item) => _playLive(item, live: false);

  void _playLive(MediaItem item, {bool live = true}) {
    Navigator.of(context).push(PageRouteBuilder(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 440),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => PlayerScreen(item: item, isLive: live),
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: WowMotion.modal, reverseCurve: Curves.easeIn);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 1.045, end: 1.0).animate(curved), child: child),
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1180;
    final rail = !wide && width >= 760;
    return Scaffold(
      backgroundColor: WowColors.ink,
      body: Atmosphere(
        child: SafeArea(
          child: Row(
            children: [
              if (wide)
                _Sidebar(section: _section, onSelect: (s) => setState(() => _section = s))
              else if (rail)
                _NavRail(section: _section, onSelect: (s) => setState(() => _section = s)),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(title: _title, index: _index, width: width, onRefresh: () => _rescan(), onSettings: () => setState(() => _section = Section.settings)),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: WowMotion.pageDuration,
                        switchInCurve: WowMotion.page,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(animation), child: child),
                        ),
                        child: KeyedSubtree(key: ValueKey(_section), child: _content(wide)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: wide || rail ? null : _BottomBar(section: _section, onSelect: (s) => setState(() => _section = s)),
    );
  }

  String get _title => switch (_section) {
        Section.home => '首页',
        Section.movies => '电影',
        Section.tv => '剧集',
        Section.live => '直播',
        Section.settings => '设置',
      };

  int get _index => switch (_section) {
        Section.home => 1,
        Section.movies => 2,
        Section.tv => 3,
        Section.live => 4,
        Section.settings => 5,
      };

  Widget _content(bool wide) {
    switch (_section) {
      case Section.home:
        return HomeView(store: widget.store, onOpen: _open, onPlay: _play);
      case Section.movies:
        return _Grid(items: widget.store.movies, title: '电影', subtitle: '${widget.store.movies.length} FILMS', onOpen: _open);
      case Section.tv:
        return _Grid(items: widget.store.series, title: '剧集', subtitle: '${widget.store.series.length} SERIES', onOpen: _open);
      case Section.live:
        return LiveView(store: widget.iptv, onPlay: _playLive);
      case Section.settings:
        return SettingsView(store: widget.store);
    }
  }

  Future<void> _rescan() async {
    for (final s in [...widget.store.sources]) {
      await widget.store.rescan(s);
    }
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.section, required this.onSelect});
  final Section section;
  final ValueChanged<Section> onSelect;

  static const _items = [
    (Section.home, Icons.home_rounded, '首页', 'HOME'),
    (Section.movies, Icons.movie_outlined, '电影', 'MOVIES'),
    (Section.tv, Icons.tv_rounded, '剧集', 'SERIES'),
    (Section.live, Icons.sensors_rounded, '直播', 'LIVE TV'),
    (Section.settings, Icons.settings_outlined, '设置', 'SETTINGS'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 218,
      margin: const EdgeInsets.fromLTRB(12, 12, 0, 12),
      decoration: BoxDecoration(
        color: const Color(0x6608090D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 26),
            child: Row(children: [
              Container(
                width: 30, height: 30,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [WowColors.accent, WowColors.accent2])),
                child: const Icon(Icons.play_arrow_rounded, size: 19, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text('SeeWow', style: WowType.display(20, FontWeight.w700, spacing: -0.4)),
            ]),
          ),
          for (final (s, icon, label, en) in _items)
            _SidebarRow(selected: section == s, icon: icon, label: label, en: en, onTap: () => onSelect(s)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Text('SEEWOW 1.0\nCINEMA FOR EVERY SCREEN', style: WowType.monoLabel(7.5, color: WowColors.faint.withValues(alpha: 0.7), spacing: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _SidebarRow extends StatelessWidget {
  const _SidebarRow({required this.selected, required this.icon, required this.label, required this.en, required this.onTap});
  final bool selected;
  final IconData icon;
  final String label;
  final String en;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: WowMotion.page,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            color: selected ? Colors.white.withValues(alpha: 0.09) : Colors.transparent,
          ),
          child: Row(children: [
            Icon(icon, size: 16, color: selected ? Colors.white : Colors.white.withValues(alpha: 0.45)),
            const SizedBox(width: 11),
            Text(label, style: TextStyle(fontSize: 12.5, color: selected ? Colors.white : Colors.white.withValues(alpha: 0.58), fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
            const Spacer(),
            if (selected) Text(en, style: WowType.monoLabel(7, color: WowColors.accent.withValues(alpha: 0.9), spacing: 0.8)),
          ]),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.index, required this.width, required this.onRefresh, required this.onSettings});
  final String title;
  final int index;
  final double width;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 66,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: width < 760 ? 18 : 34),
            child: Row(children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(shape: BoxShape.circle, color: WowColors.accent.withValues(alpha: 0.9)),
              ),
              const SizedBox(width: 11),
              Text(index.toString().padLeft(2, '0'), style: WowType.monoLabel(9, color: Colors.white.withValues(alpha: 0.26), spacing: 1.6)),
              const SizedBox(width: 10),
              Text(title, style: WowType.monoLabel(10, color: Colors.white.withValues(alpha: 0.55), spacing: 2.2)),
              const Spacer(),
          Container(
            height: 30,
            width: width < 900 ? 150 : 220,
            padding: const EdgeInsets.symmetric(horizontal: 11),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.045), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
            child: Row(children: [
              Icon(Icons.search_rounded, size: 14, color: Colors.white.withValues(alpha: 0.35)),
              const SizedBox(width: 7),
              Expanded(child: Text('搜索影片、剧集…', style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)))),
              Text('⌘K', style: WowType.monoLabel(7.5, color: Colors.white.withValues(alpha: 0.24), spacing: 0.6)),
            ]),
          ),
          const SizedBox(width: 10),
              _IconTap(icon: Icons.sync_rounded, onTap: onRefresh),
              const SizedBox(width: 6),
              _IconTap(icon: Icons.settings_outlined, onTap: onSettings),
            ]),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.white.withValues(alpha: 0.08), Colors.white.withValues(alpha: 0.015)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IconTap extends StatelessWidget {
  const _IconTap({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 30, height: 30,
        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05), border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
        child: Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.65)),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.section, required this.onSelect});
  final Section section;
  final ValueChanged<Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xF20A0C11), border: Border(top: BorderSide(color: Color(0x14FFFFFF)))),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        for (final (s, icon, label) in const [
          (Section.home, Icons.home_rounded, '首页'),
          (Section.movies, Icons.movie_outlined, '电影'),
          (Section.tv, Icons.tv_rounded, '剧集'),
          (Section.live, Icons.sensors_rounded, '直播'),
          (Section.settings, Icons.settings_outlined, '设置'),
        ])
          Pressable(
            onTap: () => onSelect(s),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: section == s ? Colors.white : Colors.white.withValues(alpha: 0.35)),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 9, color: section == s ? Colors.white : Colors.white.withValues(alpha: 0.35))),
            ]),
          ),
      ]),
    );
  }
}

enum _LibraryFilter { all, unwatched, favorites }

class _Grid extends StatefulWidget {
  const _Grid({required this.items, required this.title, required this.subtitle, required this.onOpen});
  final List<MediaItem> items;
  final String title;
  final String subtitle;
  final void Function(MediaItem) onOpen;

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  _LibraryFilter _filter = _LibraryFilter.all;
  bool _byTitle = false;

  List<MediaItem> get _visible {
    final list = switch (_filter) {
      _LibraryFilter.all => [...widget.items],
      _LibraryFilter.unwatched => widget.items.where((i) => i.progress < 0.02 && !i.watched).toList(),
      _LibraryFilter.favorites => widget.items.where((i) => i.isFavorite).toList(),
    };
    if (_byTitle) {
      list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else {
      list.sort((a, b) => (b.addedAt ?? DateTime(1970)).compareTo(a.addedAt ?? DateTime(1970)));
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final gutter = WowSpace.gutter(width);
    final items = _visible;
    return LayoutBuilder(builder: (context, c) {
      final avail = c.maxWidth - gutter * 2;
      final cols = ((avail + 22) / (176 + 22)).floor().clamp(2, 8);
      final tileW = ((avail - 22 * (cols - 1)) / cols).clamp(140.0, 240.0);
      final ratio = tileW / (tileW * 1.5 + 54);
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: WowColors.accent.withValues(alpha: 0.9))),
                      const SizedBox(width: 10),
                      Text('LIBRARY', style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.34), spacing: 2.4)),
                      const Spacer(),
                      Pressable(
                        onTap: () => setState(() => _byTitle = !_byTitle),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.swap_vert_rounded, size: 14, color: Colors.white.withValues(alpha: 0.45)),
                          const SizedBox(width: 5),
                          Text(_byTitle ? '片名' : '最近添加',
                              style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.5), spacing: 1.4)),
                        ]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(widget.title, style: WowType.display(46, FontWeight.w400, spacing: -1.2, height: 1.0)),
                      const SizedBox(width: 16),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Text('${items.length.toString().padLeft(2, '0')}  ${{'电影': 'FILMS', '剧集': 'SERIES'}[widget.title] ?? ''}',
                            style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.3), spacing: 2.2)),
                      ),
                      const Spacer(),
                      for (final (f, label) in const [
                        (_LibraryFilter.all, '全部'),
                        (_LibraryFilter.unwatched, '未看'),
                        (_LibraryFilter.favorites, '收藏'),
                      ]) ...[
                        _FilterChip(label: label, selected: _filter == f, onTap: () => setState(() => _filter = f)),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, 26, gutter, 70),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                childAspectRatio: ratio,
                crossAxisSpacing: 22,
                mainAxisSpacing: 30,
              ),
              delegate: SliverChildBuilderDelegate(
                (_, i) => RiseIn(
                  delay: Duration(milliseconds: math.min(i * 26, 320)),
                  child: PosterTile(item: items[i], width: tileW, onTap: () => widget.onOpen(items[i])),
                ),
                childCount: items.length,
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: WowMotion.pageDuration,
        curve: WowMotion.page,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
          border: Border.all(color: Colors.white.withValues(alpha: selected ? 0.26 : 0.10)),
        ),
        child: Text(label,
            style: WowType.monoLabel(8.5,
                weight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? Colors.white.withValues(alpha: 0.92) : Colors.white.withValues(alpha: 0.45),
                spacing: 1.0)),
      ),
    );
  }
}

class _NavRail extends StatelessWidget {
  const _NavRail({required this.section, required this.onSelect});
  final Section section;
  final ValueChanged<Section> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      margin: const EdgeInsets.fromLTRB(10, 10, 0, 10),
      decoration: BoxDecoration(
        color: const Color(0x6608090D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [WowColors.accent, WowColors.accent2])),
            child: const Icon(Icons.play_arrow_rounded, size: 21, color: Colors.white),
          ),
          const SizedBox(height: 18),
          for (final (s, icon, label, _) in _Sidebar._items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Pressable(
                onTap: () => onSelect(s),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: WowMotion.page,
                  width: 56,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: section == s ? Colors.white.withValues(alpha: 0.10) : Colors.transparent,
                  ),
                  child: Column(children: [
                    Icon(icon, size: 19, color: section == s ? Colors.white : Colors.white.withValues(alpha: 0.5)),
                    const SizedBox(height: 4),
                    Text(label, style: WowType.monoLabel(7.5, color: section == s ? Colors.white.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.38), spacing: 0.8)),
                  ]),
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('1.0', style: WowType.monoLabel(7.5, color: WowColors.faint.withValues(alpha: 0.6), spacing: 1.2)),
          ),
        ],
      ),
    );
  }
}