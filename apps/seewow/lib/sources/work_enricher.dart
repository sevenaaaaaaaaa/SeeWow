import '../domain/media_metadata.dart';
import '../metadata/metadata_source.dart';
import 'work_aggregator.dart';

/// 给作品行补豆瓣：评分、海报、简介。
///
/// 三条克制，都是被真实接口教出来的：
///
/// 1. **只补前 N 部**。豆瓣对突发请求会静默返回空数组（实测约 20 次/窗口，
///    40 秒才恢复），一次给 40 部作品逐条查等于自己把接口打死。
/// 2. **已经有评分的跳过**，不发第二次请求。
/// 3. **失败就是失败**：单条失败只留原样，不写 0 分、不写假海报。
class WorkEnricher {
  WorkEnricher({
    required this.source,
    this.maxWorks = 8,
    this.gap = const Duration(milliseconds: 350),
  });

  final MetadataSource source;

  /// 一次搜索最多补几部。默认 8：够填满首屏，又不至于触发限流。
  final int maxWorks;

  /// 每部之间歇一下。
  final Duration gap;

  /// 返回补全后的新列表；顺序与输入一致，未补的条目原样返回。
  Future<List<Work>> enrich(
    List<Work> works, {
    void Function(int done, int total)? onProgress,
  }) async {
    final result = List<Work>.from(works);
    final targets = <int>[];
    for (var i = 0; i < result.length && targets.length < maxWorks; i++) {
      if (result[i].rating != null) continue;
      targets.add(i);
    }
    if (targets.isEmpty) return result;

    var done = 0;
    for (final index in targets) {
      final work = result[index];
      try {
        final candidates = await source.search(
          work.title,
          series: true,
          year: work.year,
        );
        final match = _pick(work, candidates);
        if (match != null) {
          result[index] = work.enrich(
            posterUrl: match.posterUrl,
            rating: match.rating,
            overview: match.overview,
            year: match.year,
          );
        }
      } catch (_) {
        // 单个作品查不到不影响整批。
      }
      done++;
      onProgress?.call(done, targets.length);
      if (gap > Duration.zero) await Future<void>.delayed(gap);
    }
    return result;
  }

  /// 只接受「片名归一化后相同」且年份相容的候选，其余一律不认。
  static MediaMetadata? _pick(Work work, List<MediaMetadata> candidates) {
    final key = WorkAggregator.normalizeTitle(work.title);
    for (final candidate in candidates) {
      if (WorkAggregator.normalizeTitle(candidate.title) != key) continue;
      if (work.year != null && candidate.year != null) {
        if ((work.year! - candidate.year!).abs() > 1) continue;
      }
      return candidate;
    }
    return null;
  }
}
