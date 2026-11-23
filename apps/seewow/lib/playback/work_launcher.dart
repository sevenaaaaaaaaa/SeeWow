import '../domain/media_item.dart';
import '../sources/cms_vod_client.dart';
import '../sources/work_aggregator.dart';

/// 起播器：把一个 [Work] 变成「现在就能播的那个地址」。
///
/// 三件事，缺一件就会退回到「让用户自己挑源」：
///
/// 1. **排序**：沿用作品聚合的排名（直连优先、清晰度、集数），本地有货的先算。
/// 2. **失败切源**：某个源的地址拿不到（解析失败、HTTP 4xx、没有直链集数），
///    自动换下一个源，并把这次失败记下来，下次优先跳过——采集站挂掉是常态，
///    不该由用户记住哪个站坏了。
/// 3. **一条路径造条目**：界面、详情页、启动器共用同一个 MediaItem 构造，
///    避免"从这里播和从那里播参数不一样"这类鬼问题。
class WorkLauncher {
  WorkLauncher({this.maxAttempts = 3});

  /// 一次起播最多试几个源。
  final int maxAttempts;

  /// 作品 id → 失败过的站点 id。只在内存里：重启后重新试一遍，
  /// 因为采集站经常几分钟就恢复。
  final Map<String, Set<String>> _failed = {};

  bool hasFailed(Work work, WorkSource source) =>
      _failed[work.id]?.contains(source.siteId) ?? false;

  /// 按「上次是否失败」重排：没失败过的在前，其余保持原排名。
  List<WorkSource> ranked(Work work) => [
    for (final source in work.sources)
      if (!hasFailed(work, source)) source,
    for (final source in work.sources)
      if (hasFailed(work, source)) source,
  ];

  /// 起播。[prepare] 与播放器用的是同一条预处理路径（本地缓存、鉴权头等）。
  Future<WorkLaunchResult> launch(
    Work work, {
    Future<MediaItem> Function(MediaItem item)? prepare,
    WorkSource? prefer,
    void Function(String message)? onSkip,
  }) async {
    final order = [
      if (prefer != null) prefer,
      ...ranked(work).where((s) => prefer == null || s.siteId != prefer.siteId),
    ];
    if (order.isEmpty) {
      return const WorkLaunchResult(
        item: null,
        reasons: ['这部作品还没有可用的源'],
      );
    }

    final reasons = <String>[];
    var attempts = 0;
    for (final source in order) {
      if (attempts >= maxAttempts) break;
      attempts++;
      final episode = _firstPlayable(source);
      if (episode == null) {
        _failed.putIfAbsent(work.id, () => {}).add(source.siteId);
        reasons.add('${source.siteName}：没有可直连的集数');
        onSkip?.call('${source.siteName} 没有可直连地址，换下一个源');
        continue;
      }
      var item = _itemFrom(work, source, episode);
      if (prepare != null) {
        try {
          item = await prepare(item);
        } catch (error) {
          _failed.putIfAbsent(work.id, () => {}).add(source.siteId);
          reasons.add('${source.siteName}：${_short(error)}');
          onSkip?.call('${source.siteName} 打不开，换下一个源');
          continue;
        }
      }
      return WorkLaunchResult(
        item: item,
        source: source,
        episodeName: episode.name,
        reasons: reasons,
      );
    }
    return WorkLaunchResult(item: null, reasons: reasons);
  }

  /// 上报一次播放期失败（例如播放器报错），下次起播优先绕开这个源。
  void reportFailure(Work work, WorkSource source) {
    _failed.putIfAbsent(work.id, () => {}).add(source.siteId);
  }

  void clearFailures(String workId) => _failed.remove(workId);

  static CmsVodEpisode? _firstPlayable(WorkSource source) {
    for (final group in source.hit.item.sources) {
      for (final episode in group.episodes) {
        if (episode.directPlay) return episode;
      }
    }
    return null;
  }

  static MediaItem _itemFrom(
    Work work,
    WorkSource source,
    CmsVodEpisode episode,
  ) {
    final api = Uri.tryParse(source.hit.site.api);
    return MediaItem(
      id: 'online:${source.siteId}:${source.hit.item.id}:${episode.url.hashCode}',
      sourceId: 'online-${source.siteId}',
      kind: MediaKind.episode,
      title: '${source.hit.item.name} · ${episode.name}',
      locator: episode.url,
      showTitle: source.hit.item.name,
      year: work.year ?? int.tryParse(source.hit.item.year),
      posterUrl: source.hit.item.pic.isEmpty ? work.posterUrl : source.hit.item.pic,
      overview: work.overview.isNotEmpty
          ? work.overview
          : source.hit.item.content,
      httpHeaders: {
        'User-Agent': 'okhttp/3.15',
        if (api != null) 'Referer': api.origin,
      },
    );
  }

  static String _short(Object error) {
    final text = error.toString();
    return text.startsWith('FormatException: ')
        ? text.substring('FormatException: '.length)
        : text;
  }
}

class WorkLaunchResult {
  const WorkLaunchResult({
    required this.item,
    this.source,
    this.episodeName,
    this.reasons = const [],
  });

  final MediaItem? item;
  final WorkSource? source;
  final String? episodeName;

  /// 失败/跳过的原因，按尝试顺序。界面要显示它，而不是只说「播放失败」。
  final List<String> reasons;

  bool get ok => item != null;

  String get summary => ok
      ? '从 ${source!.siteName} 起播'
      : reasons.isEmpty
      ? '没有可用的源'
      : reasons.join('；');
}
