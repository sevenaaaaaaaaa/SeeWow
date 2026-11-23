import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import 'metadata_registry.dart';

/// 一个条目的刮削结果。
enum BatchScrapeStatus {
  /// 找到了足够可信的匹配并写进片库。
  matched,

  /// 有意不动：已手动确认过、信息已完整、类型不参与刮削。
  skipped,

  /// 试过但没成：没搜到、匹配不足、接口失败。
  failed,
}

class BatchScrapeOutcome {
  const BatchScrapeOutcome({
    required this.itemId,
    required this.title,
    required this.status,
    required this.detail,
    this.provider,
  });

  final String itemId, title;
  final BatchScrapeStatus status;

  /// 一句人话：为什么跳过、为什么失败、命中了哪个源的哪条。
  final String detail;

  final String? provider;

  bool get ok => status == BatchScrapeStatus.matched;
}

class BatchScrapeReport {
  const BatchScrapeReport({
    required this.outcomes,
    required this.stopped,
  });

  final List<BatchScrapeOutcome> outcomes;

  /// 用户中途按了停止。
  final bool stopped;

  int get matched =>
      outcomes.where((o) => o.status == BatchScrapeStatus.matched).length;
  int get skipped =>
      outcomes.where((o) => o.status == BatchScrapeStatus.skipped).length;
  int get failed =>
      outcomes.where((o) => o.status == BatchScrapeStatus.failed).length;

  /// 给界面的一行总结。
  String get summary => stopped
      ? '已停止：处理 ${outcomes.length} 个 · 写入 $matched · 跳过 $skipped · 失败 $failed'
      : '处理 ${outcomes.length} 个 · 写入 $matched · 跳过 $skipped · 失败 $failed';
}

/// 批量刮削：给一批条目自动补「封面 / 作品信息」。
///
/// 三条硬规则，都是为了不把片库搞脏：
///
/// 1. **只补空白**：只写条目缺的字段，已有海报或简介不会被替换。
/// 2. **不碰用户确认过的**：`metadata.reviewed == true` 说明人已经看过并确认，
///    自动流程一律跳过——自动化的价值在省掉重复劳动，不在于覆盖人的判断。
/// 3. **匹配要过门槛**：片名归一化后相似度不足、或年份差超过一年，宁可判失败
///    也不写一条错的海报。同名不同片（短剧 vs 电影）在豆瓣上非常常见。
class BatchScraper {
  BatchScraper({
    required this.registry,
    // 默认单并发：豆瓣对连续请求会返回空结果（不是报错，是「没有」），
    // 两条并飞时实测 5 条里 4 条落空，单条慢慢问全部命中。
    this.concurrency = 1,
    this.gap = const Duration(milliseconds: 400),
    this.fillOverview = false,
  });

  final MetadataRegistry registry;

  /// 同时在飞的请求数。豆瓣对突发请求敏感，默认只开两条。
  final int concurrency;

  /// 每轮之间歇一下，别把免费接口当自家服务器。
  final Duration gap;

  /// 是否额外抓简介。简介要再发一次详情请求，请求量翻倍，所以默认关：
  /// 先保证封面与评分能跑完一整批，需要简介的人自己打开。
  final bool fillOverview;

  /// 片名相似度门槛（0–1）。0.62 是「流浪地球」对「流浪地球2」这种近似
  /// 能过、但对「流浪地球」对「火星救援」不能过的位置。
  static const similarityFloor = 0.62;

  Future<BatchScrapeReport> run(
    List<MediaItem> items, {
    required Future<void> Function(String itemId, MediaMetadata match) apply,
    void Function(int done, int total, BatchScrapeOutcome latest)? onProgress,
    bool Function()? cancelled,
  }) async {
    final outcomes = <BatchScrapeOutcome>[];
    var index = 0;
    var stopped = false;

    Future<void> worker() async {
      while (true) {
        if (cancelled?.call() == true) {
          stopped = true;
          return;
        }
        final current = index++;
        if (current >= items.length) return;
        final item = items[current];
        final outcome = await _scrapeOne(item, apply);
        outcomes.add(outcome);
        onProgress?.call(outcomes.length, items.length, outcome);
        if (gap > Duration.zero) await Future<void>.delayed(gap);
      }
    }

    final lanes = concurrency < 1 ? 1 : concurrency;
    await Future.wait([for (var i = 0; i < lanes; i++) worker()]);
    return BatchScrapeReport(outcomes: outcomes, stopped: stopped);
  }

  Future<BatchScrapeOutcome> _scrapeOne(
    MediaItem item,
    Future<void> Function(String itemId, MediaMetadata match) apply,
  ) async {
    final title = item.displayTitle;

    if (item.kind == MediaKind.audio) {
      return _skip(item, '音频条目不在刮削范围');
    }
    final existing = item.metadata;
    if (existing != null && existing.reviewed) {
      return _skip(item, '已手动确认过，自动流程不改');
    }
    final hasPoster = (existing?.posterUrl ?? '').isNotEmpty;
    final hasOverview = (existing?.overview ?? '').isNotEmpty;
    if (hasPoster && hasOverview) {
      return _skip(item, '封面与简介都已齐全');
    }

    try {
      var search = await registry.search(
        title,
        series: item.kind == MediaKind.episode,
        year: item.year,
        minimum: 1,
      );
      // 空结果不等于「不存在」：免费接口在连续请求下会先装成「没有」。
      // 分级退避重试两次，共约 2.3 秒；再空就认了，不把失败拖成重试风暴。
      for (final wait in const [
        Duration(milliseconds: 700),
        Duration(milliseconds: 1600),
      ]) {
        if (search.results.isNotEmpty) break;
        await Future<void>.delayed(wait);
        search = await registry.search(
          title,
          series: item.kind == MediaKind.episode,
          year: item.year,
          minimum: 1,
        );
      }
      final best = _pickBest(title, item.year, search.results);
      if (best == null) {
        final why = search.attempts
            .where((a) => !a.ok)
            .map((a) => '${a.label} ${a.error}')
            .join(' · ');
        return _fail(
          item,
          why.isEmpty ? '没有足够接近的匹配（相似度或年份不过关）' : '没有匹配；$why',
        );
      }

      // 搜索只给摘要，简介要再取一次详情（fillOverview 打开时才发）。
      MediaMetadata detail = best;
      final source = registry.byId(best.provider);
      final needsDetail =
          best.overview.isEmpty && fillOverview || best.rating == null;
      if (source != null && needsDetail) {
        try {
          detail = await source.details(best);
        } catch (_) {
          // 详情失败不该让整条失败：摘要里的海报和片名照样能用。
          detail = best;
        }
      }

      // 只在条目缺的字段上落笔；已有的内容（包括 AI 配图）一律保留。
      final merged = mergeMetadata(
        existing ?? _emptyFor(item),
        detail,
      );
      await apply(item.id, merged);
      final added = [
        if (!hasPoster && (merged.posterUrl ?? '').isNotEmpty) '封面',
        if (!hasOverview && merged.overview.isNotEmpty) '简介',
        if ((existing?.rating == null) && merged.rating != null) '评分',
      ];
      return BatchScrapeOutcome(
        itemId: item.id,
        title: title,
        status: BatchScrapeStatus.matched,
        detail: added.isEmpty
            ? '命中 ${providerLabel(detail.provider)}，无新字段可填'
            : '命中 ${providerLabel(detail.provider)}：补了 ${added.join('、')}',
        provider: detail.provider,
      );
    } catch (error) {
      return _fail(item, error is FormatException ? error.message : '刮削失败');
    }
  }

  static MediaMetadata _emptyFor(MediaItem item) => MediaMetadata(
    id: 0,
    mediaType: item.kind == MediaKind.episode ? 'tv' : 'movie',
    title: item.title,
    overview: '',
    genres: const [],
    duration: 0,
    provider: '',
    originalTitle: '',
    originalLanguage: '',
    language: '',
    // 自动刮来的结果不算「人确认过」，否则下一轮永远跳过它。
    reviewed: false,
  );

  BatchScrapeOutcome _skip(MediaItem item, String why) => BatchScrapeOutcome(
    itemId: item.id,
    title: item.displayTitle,
    status: BatchScrapeStatus.skipped,
    detail: why,
  );

  BatchScrapeOutcome _fail(MediaItem item, String why) => BatchScrapeOutcome(
    itemId: item.id,
    title: item.displayTitle,
    status: BatchScrapeStatus.failed,
    detail: why,
  );

  /// 在所有候选里挑一条「够像」的；一条都不够像就返回 null。
  static MediaMetadata? _pickBest(
    String title,
    int? year,
    List<MediaMetadata> candidates,
  ) {
    MediaMetadata? best;
    var bestScore = 0.0;
    for (final candidate in candidates) {
      final score = _similarity(title, candidate.title);
      // 年份是硬门槛：差一年以上直接不看，免得给 2024 的片子配 1999 的海报。
      if (year != null && candidate.year != null) {
        final delta = (year - candidate.year!).abs();
        if (delta > 1) continue;
      }
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    if (best == null) return null;
    // 年份有一边不知道，就没有第二道闸：这时只认「几乎一模一样」的标题。
    final unsureYear = year == null || best.year == null;
    final floor = unsureYear ? 0.9 : similarityFloor;
    return bestScore >= floor ? best : null;
  }

  /// 归一化后的二元组相似度（Dice / Sørensen）。
  ///
  /// 选它而不是编辑距离：中文标题短，编辑距离对「流浪地球」vs「流浪地球2」
  /// 和「流浪地球」vs「流浪火星」给的分差不多；二元组能区分开。
  static double _similarity(String a, String b) {
    final left = _normalize(a);
    final right = _normalize(b);
    if (left.isEmpty || right.isEmpty) return 0;
    if (left == right) return 1;
    final leftPairs = _bigrams(left);
    final rightPairs = _bigrams(right);
    if (leftPairs.isEmpty || rightPairs.isEmpty) return 0;
    var hits = 0;
    final pool = Map<String, int>.from(rightPairs);
    for (final entry in leftPairs.entries) {
      final available = pool[entry.key] ?? 0;
      if (available <= 0) continue;
      final used = entry.value < available ? entry.value : available;
      hits += used;
      pool[entry.key] = available - used;
    }
    final total = (left.length - 1) + (right.length - 1);
    return total <= 0 ? 0 : 2 * hits / total;
  }

  static Map<String, int> _bigrams(String value) {
    final map = <String, int>{};
    for (var i = 0; i + 1 < value.length; i++) {
      final pair = value.substring(i, i + 2);
      map[pair] = (map[pair] ?? 0) + 1;
    }
    return map;
  }

  /// 去掉季集号、标点、空白与全角差异，只留下片名本体。
  static String _normalize(String value) {
    var text = value.toLowerCase();
    // 常见发布组噪声：.2024.2160p.WEB-DL、[第01集]、S01E02…
    text = text.replaceAll(
      RegExp(r'[\.\-_\[\]\(\)《》【】\s]+'),
      '',
    );
    text = text.replaceAll(
      RegExp(r'(s\d{1,2}e\d{1,3})|(\d{3,4}p)|(web-?dl)|(bluray)|(hdtv)|(x26[45])|(hevc)|(aac)'),
      '',
    );
    text = text.replaceAll(RegExp(r'第\d+[集话期]'), '');
    // 注意：不剥结尾的续集数字——「流浪地球2」和「流浪地球」是两部片。
    return text.trim();
  }
}
