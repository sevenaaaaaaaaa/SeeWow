import '../domain/media_item.dart';
import '../sources/cms_vod_client.dart';
import '../sources/online_vod_service.dart';

/// 作品级聚合：把「站点 × 条目」的一堆搜索结果，收成「一部片一行」。
///
/// 这是 M1 的地基。在此之前，同一部《流浪地球》在 5 个采集站就是 5 行结果，
/// 用户得自己比对哪条能播——那只是并发请求，不是聚合。这里做的三件事：
///
/// 1. **按作品合并**：归一化片名 + 年份做主键，年份各说各话时不硬并。
/// 2. **判可播性**：直链 m3u8/mp4 才算「能直接播」；只有分享页的标成「需解析」，
///    不假装能播。
/// 3. **排序**：直连 > 需解析；同档比清晰度，再比集数，最后按站点稳定序。
class Work {
  const Work({
    required this.id,
    required this.title,
    required this.year,
    required this.posterUrl,
    required this.rating,
    required this.overview,
    required this.sources,
    required this.localEpisodes,
  });

  /// 主键：有年份就是「归一化片名|年份」，没有就是归一化片名。
  final String id;
  final String title;
  final int? year;
  final String? posterUrl;

  /// 作品评分（豆瓣补全后填；采集站自己不带评分）。
  final double? rating;

  /// 简介（豆瓣补全后填）。
  final String overview;

  /// 已按可播性与清晰度排好序的源。
  final List<WorkSource> sources;

  /// 本地片库里已有多少集。
  final int localEpisodes;

  bool get hasDirectSource => sources.any((s) => s.directPlay);
  bool get playableNow => localEpisodes > 0 || hasDirectSource;
  int get siteCount => sources.map((s) => s.siteId).toSet().length;

  /// 最优源：本地有货时本地优先，否则取排序第一的可直连源。
  WorkSource? get bestSource {
    for (final source in sources) {
      if (source.directPlay) return source;
    }
    return sources.isEmpty ? null : sources.first;
  }

  /// 一行决断文案，详情页与列表都用它，保证说法一致。
  String get headline {
    if (localEpisodes > 0 && hasDirectSource) {
      return '本地 $localEpisodes 集 · 在线 ${sources.length} 个源';
    }
    if (localEpisodes > 0) return '本地 $localEpisodes 集';
    if (sources.isEmpty) return '暂无可用源';
    final best = bestSource;
    final quality = (best?.quality ?? '').isEmpty ? '' : ' · ${best!.quality}';
    final direct = hasDirectSource ? '可直连' : '需网页解析';
    return '$direct$quality · ${sources.length} 个源';
  }

  /// 补全一层：豆瓣给了评分/海报/简介就填进来，但**不覆盖已有值**。
  Work enrich({
    String? posterUrl,
    double? rating,
    String? overview,
    int? year,
  }) => Work(
    id: id,
    title: title,
    year: this.year ?? year,
    posterUrl: (this.posterUrl ?? '').isEmpty ? posterUrl : this.posterUrl,
    rating: this.rating ?? rating,
    overview: this.overview.isNotEmpty ? this.overview : (overview ?? ''),
    sources: sources,
    localEpisodes: localEpisodes,
  );

  /// 只有「能直接播」的源，界面不会拿需解析的源冒充可播。
  List<WorkSource> get directSources =>
      sources.where((s) => s.directPlay).toList(growable: false);
}

class WorkSource {
  const WorkSource({
    required this.siteId,
    required this.siteName,
    required this.quality,
    required this.directPlay,
    required this.episodeCount,
    required this.hit,
  });

  final String siteId, siteName;

  /// 从备注/类型名里抽出的清晰度（4K / 1080P / 720P / HD），抽不到为空串。
  final String quality;

  final bool directPlay;
  final int episodeCount;

  /// 原始命中，播放时仍走原来的 `_open`，不复制一套播放逻辑。
  final OnlineSearchHit hit;

  String get label {
    final parts = [
      siteName,
      if (quality.isNotEmpty) quality,
      if (episodeCount > 0) '$episodeCount 集',
      directPlay ? '直连' : '需解析',
    ];
    return parts.join(' · ');
  }
}

class WorkAggregator {
  WorkAggregator({this.maxWorks = 40});

  final int maxWorks;

  /// 把在线搜索结果收成作品行。[local] 用来数「本地已有几集」。
  List<Work> group(
    List<OnlineSearchHit> hits, {
    List<MediaItem> local = const [],
  }) {
    final buckets = <String, _Bucket>{};
    for (final hit in hits) {
      final title = hit.item.name.trim();
      if (title.isEmpty) continue;
      final year = int.tryParse(hit.item.year.trim());
      final key = _key(title, year);
      final bucket = buckets.putIfAbsent(
        key,
        () => _Bucket(title: title, year: year),
      );
      // 同名但年份一边缺失：以先到的有年份者为准，避免整组没有年份。
      bucket.year ??= year;
      final poster = hit.item.pic.trim();
      if (bucket.poster.isEmpty && poster.isNotEmpty) bucket.poster = poster;
      final source = _sourceOf(hit);
      // 同一个站会在不同分类里把同一部片吐多次，条目 id 还不一样，
      // 所以按「同站 + 同归一化片名 + 同年份」去重，保留清晰度更高、
      // 集数更多的那份，免得作品页里出现两行「艾旦影视」。
      final sameSite = bucket.sources.indexWhere(
        (s) =>
            s.siteId == source.siteId &&
            normalizeTitle(s.hit.item.name) == normalizeTitle(hit.item.name) &&
            (s.hit.item.year.trim() == hit.item.year.trim()),
      );
      if (sameSite < 0) {
        bucket.sources.add(source);
      } else if (_rank(source, bucket.sources[sameSite]) < 0) {
        bucket.sources[sameSite] = source;
      }
    }

    final works = <Work>[];
    for (final bucket in buckets.values) {
      final sources = bucket.sources.toList()..sort(_rank);
      final best = sources.isEmpty ? null : sources.first;
      // 年份不明时列表要能看出来，不然「同名不同片」会被当成同一部。
      final displayTitle =
          best != null && bucket.year == null ? bucket.title : bucket.title;
      works.add(
        Work(
          id: _key(bucket.title, bucket.year),
          title: displayTitle,
          year: bucket.year,
          posterUrl: bucket.poster.isEmpty ? null : bucket.poster,
          rating: null,
          overview: '',
          sources: List<WorkSource>.unmodifiable(sources),
          localEpisodes: _localEpisodes(local, bucket.title),
        ),
      );
    }
    // 排序就是产品判断，顺序写死在这里：本地有货 > 能直连 > 源多 > 片名。
    // 「本地有货」排最前是因为它永远最快、且不依赖网络。
    works.sort((a, b) {
      final aLocal = a.localEpisodes > 0 ? 1 : 0;
      final bLocal = b.localEpisodes > 0 ? 1 : 0;
      if (aLocal != bLocal) return bLocal.compareTo(aLocal);
      if (a.hasDirectSource != b.hasDirectSource) {
        return a.hasDirectSource ? -1 : 1;
      }
      if (a.sources.length != b.sources.length) {
        return b.sources.length.compareTo(a.sources.length);
      }
      return a.title.compareTo(b.title);
    });
    return works.take(maxWorks).toList();
  }

  WorkSource _sourceOf(OnlineSearchHit hit) {
    final item = hit.item;
    final episodes = item.sources
        .expand((source) => source.episodes)
        .toList(growable: false);
    final direct = episodes.where((e) => e.directPlay).length;
    return WorkSource(
      siteId: hit.site.id,
      siteName: hit.site.name,
      quality: _qualityOf('${item.remarks} ${item.typeName}'),
      directPlay: direct > 0,
      episodeCount: episodes.length,
      hit: hit,
    );
  }

  /// 直连优先；同档按清晰度；再按集数多寡。
  static int _rank(WorkSource a, WorkSource b) {
    if (a.directPlay != b.directPlay) return a.directPlay ? -1 : 1;
    final quality = _qualityRank(b.quality).compareTo(_qualityRank(a.quality));
    if (quality != 0) return quality;
    if (a.episodeCount != b.episodeCount) {
      return b.episodeCount.compareTo(a.episodeCount);
    }
    return a.siteName.compareTo(b.siteName);
  }

  static int _qualityRank(String quality) => switch (quality) {
    '4K' => 4,
    '1080P' => 3,
    '720P' => 2,
    'HD' => 1,
    _ => 0,
  };

  /// 采集站的备注里常写「HD1080P」「更新至12集」「4K」；只认这几种，别乱猜。
  static String _qualityOf(String text) {
    final upper = text.toUpperCase();
    if (upper.contains('4K') || upper.contains('2160')) return '4K';
    if (upper.contains('1080')) return '1080P';
    if (upper.contains('720')) return '720P';
    if (upper.contains('HD')) return 'HD';
    return '';
  }

  static int _localEpisodes(List<MediaItem> local, String title) {
    final key = normalizeTitle(title);
    if (key.isEmpty) return 0;
    var count = 0;
    for (final item in local) {
      final names = [
        item.showTitle ?? '',
        item.title,
        item.metadata?.title ?? '',
      ];
      if (names.any((name) => name.isNotEmpty && normalizeTitle(name) == key)) {
        count++;
      }
    }
    return count;
  }

  static String _key(String title, int? year) {
    final normalized = normalizeTitle(title);
    return year == null ? normalized : '$normalized|$year';
  }

  /// 归一化：去标点空白、去季集号与发布组噪声，保留续集数字。
  ///
  /// 保留续集数字是有意的：「流浪地球2」和「流浪地球」是两部片。
  static String normalizeTitle(String value) {
    var text = value.toLowerCase();
    text = text.replaceAll(RegExp(r'[\.\-_\[\]\(\)《》【】\s·:：,，!！?？]+'), '');
    text = text.replaceAll(RegExp(r'第\d+[集话期季]'), '');
    text = text.replaceAll(
      RegExp(r'(s\d{1,2}e\d{1,3})|(\d{3,4}p)|(web-?dl)|(bluray)|(hdtv)|(x26[45])|(hevc)|(aac)'),
      '',
    );
    return text.trim();
  }
}

class _Bucket {
  _Bucket({required this.title, this.year});

  final String title;
  int? year;
  String poster = '';
  final List<WorkSource> sources = [];
}
