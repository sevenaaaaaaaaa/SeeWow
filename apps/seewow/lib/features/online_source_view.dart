import 'package:flutter/material.dart';

import '../data/iptv_store.dart';
import '../data/online_source_store.dart';
import '../design/pressable.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../domain/online_source.dart';
import '../sources/cms_vod_client.dart';
import '../sources/online_vod_service.dart';
import '../metadata/douban_client.dart';
import '../sources/work_aggregator.dart';
import '../sources/work_enricher.dart';
import 'work_detail_view.dart';
import '../playback/line_quality.dart';
import '../playback/work_launcher.dart';
import '../sources/page_stream_resolver.dart';
import '../sources/parse_component.dart';
import '../sources/subscription_reader.dart';
import '../sources/web_page_parse.dart';
import 'web_parse_screen.dart';
import '../sources/tvbox_config.dart';

/// 「在线源」：苹果CMS 采集站搜索 + TVBox 配置里的直播源导入。
///
/// 只用纯 HTTP 接口：jar / js / py 爬虫一律不加载，配置里的 parses / spider /
/// proxy 规则同样只作为提示展示。
class OnlineSourceView extends StatefulWidget {
  const OnlineSourceView({
    super.key,
    required this.store,
    required this.iptv,
    required this.onPlay,
    this.localItems = const [],
  });

  final OnlineSourceStore store;
  final IPTVStore iptv;
  final void Function(MediaItem item, {bool live}) onPlay;

  /// 本地片库条目，用来在作品行上标「本地已有 N 集」。
  final List<MediaItem> localItems;

  @override
  State<OnlineSourceView> createState() => _OnlineSourceViewState();
}

enum _Mode { search, drama }

class _OnlineSourceViewState extends State<OnlineSourceView> {
  final _search = TextEditingController();
  final _service = OnlineVodService();
  OnlineSearchOutcome? _outcome;
  OnlineSearchOutcome? _dramaOutcome;
  List<Work> _works = const [];
  WorkEnricher? _enricher;
  _Mode _mode = _Mode.search;
  bool _busy = false;
  bool _dramaBusy = false;

  /// 正在做的那件事（读页面源码 / 搜索），给进度行用。
  String? _working;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    _enricher?.source.close();
    super.dispose();
  }

  /// 最近搜过的词：5 分钟内再搜同一个词，先把上次的结果直接摆出来，
  /// 同时后台再问一遍。采集站回话慢，重搜一次不该又从空屏开始。
  final Map<String, ({DateTime at, OnlineSearchOutcome outcome})> _cache = {};

  String _cacheKey(String word) =>
      '${widget.store.enabledSites.map((site) => site.id).join(',')}|$word';

  Future<void> _run(String keyword) async {
    final word = keyword.trim();
    if (word.isEmpty) return;
    final sites = widget.store.enabledSites;
    final key = _cacheKey(word);
    final cached = _cache[key];
    final fresh =
        cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5);
    if (fresh) {
      setState(() {
        _mode = _Mode.search;
        _outcome = cached.outcome;
        _error = null;
      });
      _showWorks(cached.outcome);
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _mode = _Mode.search;
      _busy = true;
      _error = null;
      // 换了词就先清屏；旧词的结果挂在下面会让人以为新词已经搜到了。
      if (!fresh) {
        _outcome = null;
        _works = const [];
      }
      _working = '正在问 ${sites.length} 个站点…';
    });
    try {
      final result = await _service.search(
        sites,
        word,
        onPartial: (partial) {
          if (!mounted) return;
          // 先出结果，再补评分：等 20 个站全回话才画第一行是上一版最慢的地方。
          _showWorks(partial);
          setState(() {
            _outcome = partial;
            _working =
                '已回 ${partial.answered}/${sites.length} 站 · ${_works.length} 部';
          });
        },
      );
      if (!mounted) return;
      _cache[key] = (at: DateTime.now(), outcome: result);
      setState(() => _outcome = result);
      await _rebuildWorks(result);
      if (result.isEmpty) {
        setState(
          () => _error = result.failures.isEmpty
              ? '没有找到「$word」；换一个片名试试'
              : '没有找到「$word」，${result.failures.length} 个站点没连上',
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = '搜索失败，请稍后再试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 只做聚合，不补豆瓣评分；渐进结果用它，毫秒级。
  void _showWorks(OnlineSearchOutcome outcome) {
    final works = WorkAggregator().group(
      outcome.hits,
      local: widget.localItems,
    );
    setState(() => _works = works);
  }

  Future<void> _browseDramas() async {
    setState(() {
      _dramaBusy = true;
      _error = null;
    });
    try {
      final result = await _service.browse(widget.store.enabledSites);
      if (!mounted) return;
      setState(() {
        _dramaOutcome = result;
        if (result.isEmpty) {
          _error = result.failures.isEmpty
              ? '这些站点没有放出短剧分类'
              : '没有拉到短剧：${result.failures.entries.take(3).map((e) => '${e.key}（${e.value}）').join(' · ')}';
        }
      });
    } catch (_) {
      if (mounted) setState(() => _error = '读取短剧分类失败');
    } finally {
      if (mounted) setState(() => _dramaBusy = false);
    }
  }

  /// 聚合与豆瓣补全分开：先把作品行立刻显示出来，再去慢慢补评分，
  /// 不让用户盯着一个空白列表等外部接口。
  Future<void> _rebuildWorks(OnlineSearchOutcome outcome) async {
    final works = WorkAggregator().group(
      outcome.hits,
      local: widget.localItems,
    );
    setState(() => _works = works);
    if (works.isEmpty || !mounted) return;
    final enricher = _enricher ??= WorkEnricher(source: DoubanClient());
    setState(() => _working = '正在补豆瓣评分…');
    try {
      final enriched = await enricher.enrich(
        works,
        onProgress: (done, total) {
          if (mounted) setState(() => _working = '正在补豆瓣评分 $done/$total…');
        },
      );
      if (!mounted) return;
      setState(() => _works = enriched);
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  void _setMode(_Mode mode) {
    setState(() => _mode = mode);
    if (mode == _Mode.drama && _dramaOutcome == null) _browseDramas();
  }

  void _open(OnlineSearchHit hit) {
    final sources = hit.item.sources
        .where((source) => source.playable)
        .toList();
    if (sources.isEmpty) {
      _resolveSharePage(hit);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _EpisodeSheet(
        hit: hit,
        sources: sources,
        onPick: (episode) =>
            widget.onPlay(_itemFrom(hit, episode), live: false),
      ),
    );
  }

  MediaItem _itemFrom(
    OnlineSearchHit hit,
    CmsVodEpisode episode, {
    String? url,
  }) {
    final api = Uri.tryParse(hit.site.api);
    return MediaItem(
      id: 'online:${hit.site.id}:${hit.item.id}:${episode.url.hashCode}',
      sourceId: 'online-${hit.site.id}',
      kind: MediaKind.episode,
      title: '${hit.item.name} · ${episode.name}',
      locator: url ?? episode.url,
      showTitle: hit.item.name,
      year: int.tryParse(hit.item.year),
      posterUrl: hit.item.pic.isEmpty ? null : hit.item.pic,
      overview: hit.item.content,
      httpHeaders: {
        'User-Agent': 'okhttp/3.15',
        if (api != null) 'Referer': api.origin,
      },
    );
  }

  /// 打开作品详情（纵向流），不是再弹一层「选源」。
  Future<void> _openWork(Work work) async {
    if (work.sources.isEmpty) {
      setState(() => _error = '「${work.title}」暂时没有可用的在线源');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => WorkDetailView(
        work: work,
        // 起播前测一次线路，并把结果记住：在线源的慢，一半慢在选错线路。
        launcher: WorkLauncher(
          probe: const HttpLineProbe(),
          memory: LineMemory.shared,
        ),
        onPlay: (item) {
          Navigator.of(context).pop();
          widget.onPlay(item, live: false);
        },
        onOpenEpisodes: (hit) {
          Navigator.of(context).pop();
          _open(hit);
        },
      ),
    );
  }

  /// 只有分享页的条目：先走静态解析（读源码、不执行脚本），拿不到再问要不要
  /// 用 WebView 跑一遍。这样大多数页面连确认框都不用过。
  Future<void> _resolveSharePage(OnlineSearchHit hit) async {
    final episodes = hit.item.sources
        .expand((source) => source.episodes)
        .where((episode) => !episode.directPlay && isSharePageUrl(episode.url))
        .toList();
    if (episodes.isEmpty) {
      setState(() => _error = '「${hit.item.name}」没有可直连地址，也没有可解析的分享页');
      return;
    }
    setState(() {
      _busy = true;
      _working = '正在读页面源码…';
    });
    String? reason;
    try {
      const resolver = PageStreamResolver();
      for (final episode in episodes.take(3)) {
        final result = await resolver.resolve(episode.url);
        if (!mounted) return;
        if (result.ok) {
          widget.onPlay(
            _itemFrom(hit, episode, url: result.streamUrl),
            live: false,
          );
          return;
        }
        reason = result.reason;
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _working = null;
        });
      }
    }
    if (!mounted) return;
    _offerWebParse(hit, staticReason: reason);
  }

  /// 静态解析没拿到时的退路：逐个分享页交给 WebView，一次一个，逐次确认。
  void _offerWebParse(OnlineSearchHit hit, {String? staticReason}) {
    final episodes = hit.item.sources
        .expand((source) => source.episodes)
        .where((episode) => !episode.directPlay && isSharePageUrl(episode.url))
        .toList();
    if (episodes.isEmpty) {
      setState(() => _error = '「${hit.item.name}」没有可直连地址，也没有可解析的分享页');
      return;
    }
    final component = parseComponent('webview');
    if (component == null || !component.runsHere) {
      setState(() => _error = '「${hit.item.name}」只有分享页地址；网页解析只在手机端可用');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: WowColors.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: WowColors.fade(0.08)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hit.item.name,
              style: WowType.display(22, FontWeight.w500, spacing: -0.4),
            ),
            const SizedBox(height: 4),
            Text(
              staticReason == null
                  ? '这些是分享页 / 播放器页，要在网页里跑一遍才能拿到地址'
                  : '源码里没找到直链（$staticReason），可以用网页解析试一次',
              style: WowType.monoLabel(
                9,
                color: WowColors.fade(0.4),
                spacing: 0.8,
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: episodes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final episode = episodes[index];
                  final host = Uri.tryParse(episode.url)?.host ?? '';
                  return Pressable(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _confirmParse(hit, episode);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: WowColors.fade(0.05),
                        border: Border.all(color: WowColors.fade(0.08)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              episode.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: WowType.body(
                                12.5,
                                color: WowColors.fade(0.86),
                                height: 1.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            host,
                            style: WowType.monoLabel(
                              8.5,
                              color: WowColors.fade(0.3),
                              spacing: 0.6,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.open_in_new_rounded,
                            size: 14,
                            color: WowColors.accent.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmParse(OnlineSearchHit hit, CmsVodEpisode episode) async {
    final component = parseComponent('webview')!;
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(component.name),
        content: Text(
          '${component.summary}\n\n'
          '只在这一次打开这个地址，不共享应用账号；抓到 m3u8 就会返回并交给播放器。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('继续解析'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    final parsed = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WebParseScreen(
          pageUrl: episode.url,
          title: '${hit.item.name} · ${episode.name}',
        ),
      ),
    );
    if (!mounted || parsed == null || parsed.isEmpty) {
      if (mounted) setState(() => _error = '没解析出播放地址');
      return;
    }
    widget.onPlay(_itemFrom(hit, episode, url: parsed), live: false);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 620;
    final gutter = WowSpace.gutter(width);
    final store = widget.store;
    final outcome = _mode == _Mode.drama ? _dramaOutcome : _outcome;
    final busy = _mode == _Mode.drama ? _dramaBusy : _busy;
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, wide ? 22 : 14, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: WowColors.accent.withValues(alpha: 0.9),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _mode == _Mode.drama
                      ? 'SHORT DRAMA ONLINE'
                      : 'ONLINE SOURCES',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WowType.monoLabel(
                    8.5,
                    color: WowColors.fade(0.34),
                    spacing: 2.4,
                  ),
                ),
              ),
              const Spacer(),
              // 手机上顶栏已经写着「在线源」，页面里再放一个 34px 的同名
              // 大标题就是重复：占掉 60px，还把搜索框挤到键盘后面。
              if (!wide)
                Text(
                  '${store.enabledSites.length.toString().padLeft(2, '0')}  SITES',
                  style: WowType.monoLabel(
                    9,
                    color: WowColors.fade(0.42),
                    spacing: 1.8,
                  ),
                ),
              if (!wide) const SizedBox(width: 10),
              if (wide) ...[
                _SearchField(controller: _search, onSubmit: _run, busy: _busy),
                const SizedBox(width: 10),
              ],
              _iconButton(Icons.tune_rounded, _openSites, tip: '站点与导入'),
            ],
          ),
          if (wide) ...[
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '在线源',
                  style: WowType.display(
                    46,
                    FontWeight.w400,
                    spacing: -1.2,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '${store.enabledSites.length.toString().padLeft(2, '0')}  SITES',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WowType.monoLabel(
                        8.5,
                        color: WowColors.fade(0.3),
                        spacing: 2.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: wide ? 18 : 12),
          // 手机上搜索框单独占一行、按 44 的高度给足点击面积；挤在标题右边
          // 只能塞下 168px，提示语被截掉，看上去就像一个空胶囊。
          if (!wide) ...[
            _SearchField(
              controller: _search,
              onSubmit: _run,
              busy: _busy,
              expanded: true,
            ),
            const SizedBox(height: 12),
          ],
          Container(height: 1, color: WowColors.fade(0.07)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _modeChip('片名搜索', _Mode.search),
              _modeChip('短剧', _Mode.drama),
              if (_mode == _Mode.drama)
                Text(
                  '采集站自带的短剧分类',
                  style: WowType.monoLabel(
                    8.5,
                    color: WowColors.fade(0.3),
                    spacing: 1,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (busy)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _working ??
                    (_mode == _Mode.drama
                        ? '正在读各站点的短剧分类…'
                        : '正在问 ${store.enabledSites.length} 个站点…'),
                style: WowType.monoLabel(
                  9,
                  color: WowColors.fade(0.45),
                  spacing: 1.4,
                ),
              ),
            ),
          if (outcome != null && outcome.failures.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                '没连上：${outcome.failures.entries.map((e) => '${e.key}（${e.value}）').join(' · ')}',
                style: WowType.monoLabel(
                  9,
                  color: WowColors.muted.withValues(alpha: 0.8),
                  spacing: 0.8,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _error!,
                style: WowType.body(12.5, color: WowColors.error),
              ),
            ),
          Expanded(
            child: outcome == null || _works.isEmpty
                ? _EmptyState(
                    sites: store.enabledSites.length,
                    drama: _mode == _Mode.drama,
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: _works.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final work = _works[index];
                      return _WorkRow(work: work, onTap: () => _openWork(work));
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _modeChip(String label, _Mode mode) {
    final active = _mode == mode;
    return Pressable(
      onTap: () => _setMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: active
              ? WowColors.accent.withValues(alpha: 0.16)
              : WowColors.fade(0.05),
          border: Border.all(
            color: active
                ? WowColors.accent.withValues(alpha: 0.45)
                : WowColors.fade(0.08),
          ),
        ),
        child: Text(
          label,
          style: WowType.monoLabel(
            9,
            color: active ? WowColors.accent : WowColors.fade(0.6),
            spacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {String? tip}) =>
      Tooltip(
        message: tip ?? '',
        child: Pressable(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: WowColors.fade(0.06),
              border: Border.all(color: WowColors.fade(0.1)),
            ),
            child: Icon(icon, size: 17, color: WowColors.fade(0.72)),
          ),
        ),
      );

  void _openSites() => showDialog<void>(
    context: context,
    builder: (_) => _SitesDialog(store: widget.store, iptv: widget.iptv),
  );
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onSubmit,
    this.busy = false,
    this.expanded = false,
  });
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final bool busy;

  /// 手机上占满一行：搜索是在线源页面的主操作，不该挤在标题右边当装饰。
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(expanded ? 23 : 19);
    final side = BorderSide(color: WowColors.fade(0.1));
    return SizedBox(
      width: expanded
          ? double.infinity
          : (MediaQuery.sizeOf(context).width < 760 ? 240 : 260),
      height: expanded ? 46 : 38,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final hasText = controller.text.trim().isNotEmpty;
          return TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: onSubmit,
            style: WowType.body(
              expanded ? 14 : 12.5,
              color: WowColors.fade(0.9),
            ),
            decoration: InputDecoration(
              isDense: !expanded,
              contentPadding: expanded
                  ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                  : null,
              hintText: expanded ? '输入片名，回车搜索' : '搜索片名',
              hintStyle: WowType.body(
                expanded ? 13 : 12,
                color: WowColors.fade(0.42),
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: expanded ? 18 : 16,
                color: WowColors.fade(0.45),
              ),
              suffixIconConstraints: BoxConstraints(
                minWidth: expanded ? 44 : 38,
                maxHeight: expanded ? 44 : 38,
              ),
              suffixIcon: busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.4),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasText)
                          _fieldIcon(
                            tooltip: '清空',
                            icon: Icons.close_rounded,
                            onTap: () {
                              controller.clear();
                              onSubmit('');
                            },
                          ),
                        _fieldIcon(
                          tooltip: '搜索',
                          icon: Icons.arrow_forward_rounded,
                          onTap: () => onSubmit(controller.text),
                        ),
                      ],
                    ),
              filled: true,
              fillColor: WowColors.fade(0.05),
              border: OutlineInputBorder(
                borderRadius: radius,
                borderSide: side,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: side,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: radius,
                borderSide: BorderSide(
                  color: WowColors.accent.withValues(alpha: 0.7),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _fieldIcon({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) => IconButton(
    tooltip: tooltip,
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    constraints: BoxConstraints.tightFor(
      width: expanded ? 44 : 38,
      height: expanded ? 44 : 38,
    ),
    onPressed: onTap,
    icon: Icon(icon, size: expanded ? 18 : 17, color: WowColors.fade(0.72)),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.sites, this.drama = false});
  final int sites;
  final bool drama;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.travel_explore_rounded,
          size: 40,
          color: WowColors.fade(0.14),
        ),
        const SizedBox(height: 12),
        Text(
          drama
              ? '点「短剧」读一遍各站的短剧分类'
              : sites == 0
              ? '还没有站点：点右上「站点与导入」手动加一条采集站接口'
              : '输入片名，问一遍已启用的 $sites 个采集站',
          style: WowType.body(13, color: WowColors.fade(0.42)),
        ),
        const SizedBox(height: 6),
        Text(
          '只走纯 HTTP 接口；爬虫插件不会被加载',
          style: WowType.monoLabel(
            9,
            color: WowColors.fade(0.26),
            spacing: 1.2,
          ),
        ),
      ],
    ),
  );
}

class _EpisodeSheet extends StatefulWidget {
  const _EpisodeSheet({
    required this.hit,
    required this.sources,
    required this.onPick,
  });
  final OnlineSearchHit hit;
  final List<CmsVodSource> sources;
  final void Function(CmsVodEpisode episode) onPick;

  @override
  State<_EpisodeSheet> createState() => _EpisodeSheetState();
}

class _EpisodeSheetState extends State<_EpisodeSheet> {
  int _line = 0;

  @override
  Widget build(BuildContext context) {
    final selected = widget.sources[_line];
    final source = CmsVodSource(selected.from, selected.directEpisodes);
    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.36,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: WowColors.panel,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border.all(color: WowColors.fade(0.08)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Text(
              widget.hit.item.name,
              style: WowType.display(24, FontWeight.w500, spacing: -0.4),
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.hit.site.name} · ${source.episodes.length} 集',
              style: WowType.monoLabel(
                9,
                color: WowColors.fade(0.36),
                spacing: 1.2,
              ),
            ),
            if (widget.sources.length > 1) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < widget.sources.length; i++)
                    Pressable(
                      onTap: () => setState(() => _line = i),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: i == _line
                              ? WowColors.accent.withValues(alpha: 0.18)
                              : WowColors.fade(0.05),
                          border: Border.all(
                            color: i == _line
                                ? WowColors.accent.withValues(alpha: 0.5)
                                : WowColors.fade(0.08),
                          ),
                        ),
                        child: Text(
                          widget.sources[i].from,
                          style: WowType.monoLabel(
                            9,
                            color: i == _line
                                ? WowColors.accent
                                : WowColors.fade(0.6),
                            spacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final episode in source.episodes)
                  Pressable(
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onPick(episode);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 13,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: WowColors.fade(0.055),
                        border: Border.all(color: WowColors.fade(0.08)),
                      ),
                      child: Text(
                        episode.name,
                        style: WowType.body(
                          12.5,
                          color: WowColors.fade(0.86),
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SitesDialog extends StatefulWidget {
  const _SitesDialog({required this.store, required this.iptv});
  final OnlineSourceStore store;
  final IPTVStore iptv;

  @override
  State<_SitesDialog> createState() => _SitesDialogState();
}

class _SitesDialogState extends State<_SitesDialog> {
  final _name = TextEditingController();
  final _api = TextEditingController();
  final _config = TextEditingController();
  String? _status;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _api.dispose();
    _config.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final added = await widget.store.addSite(_name.text, _api.text);
    if (!mounted) return;
    setState(() {
      _status = widget.store.toast ?? (added ? '已添加' : '没有添加');
      if (added) {
        _name.clear();
        _api.clear();
      }
    });
  }

  Future<void> _importConfig() async {
    final url = _config.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _busy = true;
      _status = '正在读取配置…';
    });
    try {
      final document = await const SubscriptionReader().read(url);
      final report = TvBoxConfig.parse(document.text, baseUri: document.uri);
      final candidates = [
        for (final site in report.playableSites)
          if (site.kind == TvBoxSiteKind.cms && site.api != null)
            OnlineSite(
              id: 'cfg-${site.key}-${site.name.hashCode}',
              name: site.name,
              api: site.api!,
            ),
      ];
      final added = await widget.store.importFromConfig(candidates);
      var playslist = 0;
      for (final live in report.lives) {
        final ok = await widget.iptv.addPlaylist(
          name: live.name,
          source: live.uri.toString(),
          epgUrl: live.epgUrl,
        );
        if (ok) playslist++;
      }
      if (!mounted) return;
      setState(() {
        _status =
            '采集站新增 $added 个（跳过 ${report.blockedCount} 个需要爬虫的）；'
            '直播源导入 $playslist 条';
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _status = error is FormatException ? error.message : '导入失败，请检查地址',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Container(
          decoration: BoxDecoration(
            color: WowColors.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: WowColors.fade(0.08)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('站点', style: WowType.display(22, FontWeight.w500)),
              const SizedBox(height: 4),
              Text(
                store.noBuiltinSources
                    ? '本版不随包内置站点 · 点「添加」填一条采集站接口，'
                          '或粘 TVBox 配置导入；直播源导入后进「直播」页'
                    : '内置 ${dedupeSites(seedOnlineSites).length} 个直连采集站 · '
                          '粘一条 TVBox 配置可再导入；直播源导入后进「直播」页',
                style: WowType.monoLabel(
                  9,
                  color: WowColors.fade(0.34),
                  spacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => store.setAll(true)),
                    child: const Text('全部启用'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => store.setAll(false)),
                    child: const Text('全部停用'),
                  ),
                  const Spacer(),
                  Text(
                    '启用 ${store.enabledSites.length} / ${store.sites.length}',
                    style: WowType.monoLabel(
                      8.5,
                      color: WowColors.fade(0.34),
                      spacing: 1,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final site in store.sites)
                      SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: site.enabled,
                        onChanged: (value) =>
                            setState(() => store.toggle(site, value)),
                        title: Text(
                          site.name,
                          style: WowType.body(
                            12.5,
                            color: WowColors.fade(0.88),
                          ),
                        ),
                        secondary: IconButton(
                          tooltip: '删除「${site.name}」',
                          onPressed: () =>
                              setState(() => store.removeSite(site)),
                          icon: const Icon(Icons.delete_outline, size: 18),
                        ),
                        subtitle: Text(
                          site.api,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WowType.monoLabel(
                            8.5,
                            color: WowColors.fade(0.3),
                            spacing: 0.4,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(flex: 2, child: _field(_name, '名称（可留空）')),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 4,
                    child: _field(_api, '接口地址，如 https://x/api.php/provide/vod'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : _add,
                    child: const Text('添加'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _field(_config, 'TVBox 配置地址（导入采集站与直播源）')),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _busy ? null : _importConfig,
                    child: const Text('导入'),
                  ),
                ],
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _status!,
                    style: WowType.body(11.5, color: WowColors.fade(0.6)),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('关闭'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String hint) => TextField(
    controller: controller,
    style: WowType.body(12, color: WowColors.fade(0.9)),
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: WowType.body(11.5, color: WowColors.fade(0.3)),
      filled: true,
      fillColor: WowColors.fade(0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: WowColors.fade(0.1)),
      ),
    ),
  );
}

/// 一行 = 一部作品。副标题直接回答「能不能看、从哪看」。
class _WorkRow extends StatelessWidget {
  const _WorkRow({required this.work, required this.onTap});

  final Work work;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    focusRadius: 14,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: WowColors.fade(0.03),
        border: Border.all(color: WowColors.fade(0.06)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 46,
              height: 66,
              child: work.posterUrl == null
                  ? ColoredBox(color: WowColors.fade(0.05))
                  : Image.network(
                      work.posterUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          ColoredBox(color: WowColors.fade(0.05)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        work.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: WowType.body(13.5, color: WowColors.text),
                      ),
                    ),
                    if (work.year != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '${work.year}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: WowColors.muted,
                          ),
                        ),
                      ),
                    if (work.rating != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '★ ${work.rating!.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: WowColors.accent,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  work.headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: work.playableNow
                        ? WowColors.accent
                        : WowColors.muted,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  work.sources.map((s) => s.siteName).take(4).join(' · ') +
                      (work.sources.length > 4 ? ' …' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: WowColors.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: WowColors.muted),
        ],
      ),
    ),
  );
}
