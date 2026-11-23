import 'package:flutter/material.dart';

import '../design/pressable.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../playback/work_launcher.dart';
import '../sources/online_vod_service.dart';
import '../sources/work_aggregator.dart';
import 'review_section.dart';

/// 作品详情：一条纵向流，不是四个弹层。
///
/// 顺序是按「用户此刻要什么」排的，不是按数据来源排的：
///   1. 能不能看 —— 一行决断 + 主按钮（一次点击就起播）
///   2. 从哪看 —— 源矩阵，每行写清清晰度/集数/直连或需解析
///   3. 是什么 —— 简介
///   4. 大家怎么说 —— 评论（点开才拉）
class WorkDetailView extends StatefulWidget {
  const WorkDetailView({
    super.key,
    required this.work,
    required this.onPlay,
    this.prepare,
    this.launcher,
    this.onOpenEpisodes,
  });

  final Work work;
  final void Function(MediaItem item) onPlay;

  /// 与播放器同一条预处理路径（缓存、鉴权头）。测试里传 null 即可。
  final Future<MediaItem> Function(MediaItem item)? prepare;

  /// 起播器可注入，便于测试失败切源。
  final WorkLauncher? launcher;

  /// 打开某个源的完整剧集列表（选集）。为空时只提供「从第 1 集起播」。
  final void Function(OnlineSearchHit hit)? onOpenEpisodes;

  @override
  State<WorkDetailView> createState() => _WorkDetailViewState();
}

class _WorkDetailViewState extends State<WorkDetailView> {
  late final WorkLauncher _launcher = widget.launcher ?? WorkLauncher();
  bool _busy = false;
  String? _notice;
  MediaItem? _playable;

  Future<void> _start({WorkSource? prefer}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    final result = await _launcher.launch(
      widget.work,
      prefer: prefer,
      prepare: widget.prepare,
      onSkip: (message) {
        if (mounted) setState(() => _notice = message);
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _playable = result.item;
      _notice = result.ok
          ? null
          : result.summary;
    });
    if (result.item != null) widget.onPlay(result.item!);
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Container(
          decoration: BoxDecoration(
            color: WowColors.panel,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
                  children: [
                    _header(work),
                    const SizedBox(height: 16),
                    _decision(work),
                    const SizedBox(height: 18),
                    _sources(work),
                    if (work.overview.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Text(
                        '故事',
                        style: WowType.monoLabel(9.5, spacing: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        work.overview,
                        style: WowType.body(
                          12.5,
                          color: WowColors.muted,
                          height: 1.8,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    ReviewSection.forWork(
                      title: work.title,
                      year: work.year,
                      series: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
                child: Row(
                  children: [
                    if (_notice != null)
                      Expanded(
                        child: Text(
                          _notice!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: WowColors.error,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(Work work) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 86,
          height: 124,
          child: (work.posterUrl ?? '').isEmpty
              ? ColoredBox(color: Colors.white.withValues(alpha: 0.05))
              : Image.network(
                  work.posterUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
        ),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              work.title,
              style: WowType.display(26, FontWeight.w500, height: 1.15),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                if (work.year != null)
                  Text(
                    '${work.year}',
                    style: TextStyle(fontSize: 12, color: WowColors.muted),
                  ),
                if (work.rating != null)
                  Text(
                    '★ ${work.rating!.toStringAsFixed(1)}',
                    style: TextStyle(fontSize: 12, color: WowColors.accent),
                  ),
                Text(
                  '${work.sources.length} 个源',
                  style: TextStyle(fontSize: 12, color: WowColors.muted),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );

  /// 一行决断：先说能不能看，再给一个按钮。
  Widget _decision(Work work) => Container(
    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      color: Colors.white.withValues(alpha: 0.035),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                work.headline,
                style: TextStyle(
                  fontSize: 12.5,
                  color: work.playableNow ? WowColors.text : WowColors.muted,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                work.hasDirectSource
                    ? '点一下从最优源开始；坏源会自动跳过'
                    : '这些源只有分享页，起播前需要解析',
                style: TextStyle(fontSize: 10.5, color: WowColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _busy || work.sources.isEmpty ? null : () => _start(),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('开始看'),
        ),
      ],
    ),
  );

  Widget _sources(Work work) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('从哪看', style: WowType.monoLabel(9.5, spacing: 1.4)),
      const SizedBox(height: 8),
      if (work.sources.isEmpty)
        Text(
          '这部作品暂时没有可用源。',
          style: TextStyle(fontSize: 12, color: WowColors.muted),
        ),
      for (final source in _launcher.ranked(work))
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Pressable(
            onTap: _busy ? null : () => _start(prefer: source),
            focusRadius: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withValues(
                  alpha: source.directPlay ? 0.045 : 0.02,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      source.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: source.directPlay
                            ? WowColors.text
                            : WowColors.muted,
                      ),
                    ),
                  ),
                  if (_launcher.hasFailed(work, source))
                    Text(
                      '上次失败',
                      style: TextStyle(fontSize: 10, color: WowColors.error),
                    ),
                  if (widget.onOpenEpisodes != null &&
                      source.episodeCount > 1) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () => widget.onOpenEpisodes!(source.hit),
                      child: const Text('选集', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Icon(
                    source.directPlay
                        ? Icons.bolt_rounded
                        : Icons.language_rounded,
                    size: 14,
                    color: source.directPlay
                        ? WowColors.accent
                        : WowColors.muted,
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}
