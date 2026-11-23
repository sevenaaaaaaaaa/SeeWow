import 'package:flutter/material.dart';

import '../design/cinema_widgets.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../domain/media_review.dart';
import '../metadata/anilist_client.dart';
import '../metadata/douban_client.dart';
import '../metadata/metadata_registry.dart';

/// 详情页的「评论」区。
///
/// 评论不在打开详情时自动拉：那会让每次点开条目都发两次外部请求。这里默认折叠，
/// 用户点「看评论」才查一次；查到几条就写清是哪个站、几个人说的，查不到也说清
/// 原因，不拿「暂无评论」糊住一次失败。
///
/// 数据源只用免密钥的两支：豆瓣（电影/剧集/动漫/短剧）和 AniList（动漫）。
class ReviewSection extends StatefulWidget {
  const ReviewSection({super.key, required this.item});

  /// 作品级评论：从在线源或搜索结果进来时没有本地条目，用片名+年份合成一个
  /// 候选，评论链路完全一样，不复制一套逻辑。
  factory ReviewSection.forWork({
    Key? key,
    required String title,
    int? year,
    bool series = true,
  }) => ReviewSection(
    key: key,
    item: MediaItem(
      id: 'work:$title|${year ?? ''}',
      sourceId: 'work',
      kind: series ? MediaKind.episode : MediaKind.movie,
      title: title,
      locator: '',
      year: year,
    ),
  );

  final MediaItem item;

  @override
  State<ReviewSection> createState() => _ReviewSectionState();
}

class _ReviewSectionState extends State<ReviewSection> {
  MetadataRegistry? _registry;
  List<MediaReview> _reviews = const [];
  String? _sourceLabel;
  String? _error;
  bool _busy = false;
  bool _loaded = false;

  @override
  void dispose() {
    _registry?.close();
    super.dispose();
  }

  MetadataRegistry get _sources =>
      _registry ??= MetadataRegistry([DoubanClient(), AniListClient()]);

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final item = widget.item;
      // 已经匹配过元数据就直接用它的 id；否则先按片名搜一次。
      var candidate = item.metadata;
      if (candidate == null || candidate.provider.isEmpty) {
        final outcome = await _sources.search(
          item.displayTitle,
          series: item.kind == MediaKind.episode,
          year: item.year,
          minimum: 1,
        );
        candidate = outcome.results.isEmpty ? null : outcome.results.first;
      }
      if (candidate == null) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _loaded = true;
          _error = '两个免费源都没找到「${item.displayTitle}」，换个片名或先匹配元数据';
        });
        return;
      }
      final preferred = switch (candidate.provider) {
        'anilist' => 'anilist',
        'douban' => 'douban',
        _ => null,
      };
      final result = await _sources.reviews(
        candidate,
        limit: 8,
        preferred: preferred,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loaded = true;
        _reviews = result.reviews;
        _sourceLabel = result.isEmpty ? null : result.label;
        _error = result.isEmpty ? (result.error ?? '这个条目没有评论') : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _loaded = true;
        _error = error is FormatException ? error.message : '评论加载失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.kind == MediaKind.audio) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 不用 Row + Spacer：详情页这一层可能拿到无界宽度，
          // flex 子节点会直接抛 "non-zero flex but incoming width constraints
          // are unbounded"。Wrap 只按内容排，宽度给多少都成立。
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const SectionTitle('大家怎么说'),
              if (_sourceLabel != null)
                Text(
                  '来自 $_sourceLabel · ${_reviews.length} 条',
                  style: TextStyle(fontSize: 11, color: WowColors.muted),
                ),
              if (!_loaded && !_busy)
                TextButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.forum_outlined, size: 16),
                  label: const Text('看评论'),
                ),
              if (_busy)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: WowColors.muted),
              ),
            ),
          if (_reviews.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final review in _reviews)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ReviewCard(review: review),
              ),
          ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final MediaReview review;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
    decoration: BoxDecoration(
      color: WowColors.panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              review.author.trim().isEmpty ? '匿名' : review.author,
              style: TextStyle(fontSize: 12, color: WowColors.text),
            ),
            Text(
              reviewSourceLabel(review.source),
              style: TextStyle(fontSize: 10, color: WowColors.muted),
            ),
            if (review.hasScore)
              Text(
                '${review.score!.toStringAsFixed(review.score! % 1 == 0 ? 0 : 1)}'
                '/${review.maxScore.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 11, color: WowColors.accent),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          review.text,
          style: WowType.body(12.5, color: WowColors.muted, height: 1.7),
        ),
      ],
    ),
  );
}
