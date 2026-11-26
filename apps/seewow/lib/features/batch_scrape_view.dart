import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../metadata/anilist_client.dart';
import '../metadata/batch_scraper.dart';
import '../metadata/douban_client.dart';
import '../metadata/metadata_registry.dart';

/// 打开「批量刮削」。`items` 就是当前列表看到的那批条目——用户筛到什么，
/// 刮的就是什么，不做「你没看见的也一起改了」这种事。
Future<void> runBatchScrape(
  BuildContext context,
  LibraryStore store,
  List<MediaItem> items, {
  MetadataRegistry? registry,
}) {
  if (items.isEmpty) return Future<void>.value();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BatchScrapeDialog(
      store: store,
      items: items,
      registry: registry,
    ),
  );
}

class BatchScrapeDialog extends StatefulWidget {
  const BatchScrapeDialog({
    super.key,
    required this.store,
    required this.items,
    this.registry,
  });

  final LibraryStore store;
  final List<MediaItem> items;

  /// 测试注入用；正常运行走免密钥的豆瓣 + AniList。
  final MetadataRegistry? registry;

  @override
  State<BatchScrapeDialog> createState() => _BatchScrapeDialogState();
}

class _BatchScrapeDialogState extends State<BatchScrapeDialog> {
  late final MetadataRegistry _registry =
      widget.registry ?? MetadataRegistry([DoubanClient(), AniListClient()]);
  final _outcomes = <BatchScrapeOutcome>[];
  bool _running = false;
  bool _cancel = false;
  bool _fillOverview = false;
  int _done = 0;
  BatchScrapeReport? _report;

  @override
  void dispose() {
    _cancel = true;
    if (widget.registry == null) _registry.close();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _running = true;
      _cancel = false;
      _outcomes.clear();
      _done = 0;
      _report = null;
    });
    final scraper = BatchScraper(
      registry: _registry,
      fillOverview: _fillOverview,
    );
    final report = await scraper.run(
      widget.items,
      apply: (itemId, match) => widget.store.applyMetadata(itemId, match),
      cancelled: () => _cancel,
      onProgress: (done, total, latest) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _outcomes.add(latest);
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = report;
    });
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final total = widget.items.length;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Container(
          decoration: BoxDecoration(
            color: WowColors.panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: WowColors.wash(0.08)),
          ),
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('批量刮削', style: WowType.display(22, FontWeight.w500)),
              const SizedBox(height: 6),
              Text(
                '给 $total 个条目补封面与作品信息 · 只用免密钥的豆瓣与 AniList · '
                '只填空白字段，已手动确认过的条目一律不动',
                style: WowType.monoLabel(
                  9,
                  color: WowColors.fade(0.42),
                  spacing: 0.6,
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _fillOverview,
                onChanged: _running
                    ? null
                    : (value) => setState(() => _fillOverview = value),
                title: Text(
                  '同时补简介',
                  style: TextStyle(fontSize: 13, color: WowColors.text),
                ),
                subtitle: Text(
                  '简介要再发一次详情请求，整批请求量翻倍，容易被站点限流；默认只补封面与评分',
                  style: TextStyle(fontSize: 11, color: WowColors.muted),
                ),
              ),
              const SizedBox(height: 6),
              if (_running || report != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: total == 0 ? null : _done / total,
                    minHeight: 4,
                    backgroundColor: WowColors.wash(0.08),
                    color: WowColors.accent,
                  ),
                ),
              if (_running)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '已处理 $_done / $total · 写入 '
                    '${_outcomes.where((o) => o.ok).length} · 跳过 '
                    '${_outcomes.where((o) => o.status == BatchScrapeStatus.skipped).length} · 失败 '
                    '${_outcomes.where((o) => o.status == BatchScrapeStatus.failed).length}',
                    style: TextStyle(fontSize: 11, color: WowColors.muted),
                  ),
                ),
              if (report != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    report.summary,
                    style: TextStyle(
                      fontSize: 12,
                      color: report.failed == 0 ? WowColors.text : WowColors.muted,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (_outcomes.isEmpty && !_running)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '开始后会逐条查片名与年份；相似度不够或年份对不上的条目会判失败，'
                    '不会写一条错的海报进去。',
                    style: TextStyle(fontSize: 12, color: WowColors.muted),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _outcomes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) =>
                        _OutcomeRow(outcome: _outcomes[index]),
                  ),
                ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Spacer(),
                  if (_running)
                    TextButton(
                      onPressed: () => setState(() => _cancel = true),
                      child: const Text('停止'),
                    )
                  else ...[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _start,
                      child: Text(_report == null ? '开始刮削' : '再刮一次'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OutcomeRow extends StatelessWidget {
  const _OutcomeRow({required this.outcome});

  final BatchScrapeOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (outcome.status) {
      BatchScrapeStatus.matched => (Icons.check_circle_outline, WowColors.accent),
      BatchScrapeStatus.skipped => (Icons.remove_circle_outline, WowColors.muted),
      BatchScrapeStatus.failed => (Icons.error_outline, WowColors.error),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                outcome.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: WowColors.text),
              ),
              Text(
                outcome.detail,
                style: TextStyle(fontSize: 11, color: WowColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
