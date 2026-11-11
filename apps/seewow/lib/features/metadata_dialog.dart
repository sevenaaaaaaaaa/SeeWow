import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/artwork.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import '../metadata/tmdb_client.dart';

Future<void> matchMetadata(
  BuildContext context,
  LibraryStore library,
  MediaItem item, {
  Future<TmdbClient> Function()? clientFactory,
}) => showDialog<void>(
  context: context,
  builder: (_) => _MetadataDialog(
    library: library,
    item: item,
    clientFactory: clientFactory,
  ),
);
Future<void> configureMetadata(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _MetadataConfig());

class TmdbCredit extends StatelessWidget {
  const TmdbCredit({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Image.asset(
        'assets/branding/tmdb.png',
        width: 88,
        height: 30,
        fit: BoxFit.contain,
        alignment: Alignment.centerLeft,
        errorBuilder: (_, _, _) => Text(
          'TMDB',
          style: TextStyle(color: WowColors.success, fontWeight: FontWeight.bold),
        ),
      ),
      const SizedBox(height: 6),
      Text(
        'This product uses the TMDB API but is not endorsed or certified by TMDB.',
        style: WowType.body(10, color: WowColors.muted),
      ),
    ],
  );
}

class _MetadataConfig extends StatefulWidget {
  const _MetadataConfig();
  @override
  State<_MetadataConfig> createState() => _MetadataConfigState();
}

class _MetadataConfigState extends State<_MetadataConfig> {
  final _token = TextEditingController();
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TmdbClient.configure(_token.text);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，请填写有效的 Read Access Token 后重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('影片信息服务'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '使用你自己的 TMDB API Read Access Token（v4 Bearer Token）。只在主动搜索、预览时发送片名和所选 TMDB ID，不上传媒体文件或片源凭据。',
              style: WowType.body(12, color: WowColors.muted),
            ),
            const SizedBox(height: 14),
            const SelectableText(
              'https://www.themoviedb.org/settings/api',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _token,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'TMDB Read Access Token',
                hintText: '保存到本机凭据存储',
              ),
            ),
            const SizedBox(height: 16),
            const TmdbCredit(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: WowColors.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('保存配置')),
    ],
  );
}

class _MetadataDialog extends StatefulWidget {
  const _MetadataDialog({
    required this.library,
    required this.item,
    this.clientFactory,
  });
  final Future<TmdbClient> Function()? clientFactory;
  final LibraryStore library;
  final MediaItem item;
  @override
  State<_MetadataDialog> createState() => _MetadataDialogState();
}

class _MetadataDialogState extends State<_MetadataDialog> {
  late final TextEditingController _query;
  TmdbClient? _client;
  List<MediaMetadata> _candidates = [];
  MediaMetadata? _selected;
  String? _error;
  bool _busy = false, _searched = false, _replaceArt = false, _applying = false;
  @override
  void initState() {
    super.initState();
    _query = TextEditingController(
      text: widget.item.showTitle ?? widget.item.title,
    );
  }

  @override
  void dispose() {
    _client?.close();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _error = null;
      _selected = null;
    });
    try {
      _client?.close();
      final client = await (widget.clientFactory ?? TmdbClient.configured)();
      if (!mounted) {
        client.close();
        return;
      }
      _client = client;
      final results = await _client!.search(
        _query.text,
        series: widget.item.kind == MediaKind.episode,
      );
      if (mounted)
        setState(() {
          _candidates = results;
          _searched = true;
        });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _preview(MediaMetadata candidate) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final match = await _client!.details(candidate);
      if (mounted) setState(() => _selected = match);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    if (_selected == null) return;
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      await widget.library.applyMetadata(
        widget.item.id,
        _selected!.withArtwork(_replaceArt),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _error = '保存失败，条目可能已移出片库，请重试');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_applying,
    child: AlertDialog(
      title: const Text('匹配影片信息'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '检查同名作品与年份，预览后确认。文件路径、观看进度、待看和片单关系会保留。剧集匹配整部剧的信息。',
                style: WowType.body(12, color: WowColors.muted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _query,
                enabled: !_busy && !_applying,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  labelText: '电影或剧集名称',
                  suffixIcon: IconButton(
                    tooltip: '搜索 TMDB',
                    onPressed: _busy || _applying ? null : _search,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: _busy || _applying
                    ? null
                    : () => configureMetadata(context),
                icon: const Icon(Icons.key, size: 16),
                label: const Text('配置 TMDB Token'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: WowColors.error,
                    ),
                  ),
                ),
              if (_searched && _candidates.isEmpty && !_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('没有匹配结果，请尝试原片名或移除文件名中的版本信息。'),
                ),
              if (_selected == null) ...[
                for (final c in _candidates)
                  ListTile(
                    enabled: !_busy && !_applying,
                    contentPadding: EdgeInsets.zero,
                    leading: SizedBox(
                      width: 40,
                      height: 56,
                      child: WowArt(
                        url: c.posterUrl,
                        fallback: const Icon(Icons.movie_outlined),
                      ),
                    ),
                    title: Text(c.title, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                      '${c.year ?? '年份未知'} · TMDB ${c.id}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _preview(c),
                  ),
              ] else ...[
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      height: 144,
                      child: WowArt(
                        url: _selected!.posterUrl,
                        fallback: const Icon(Icons.movie_outlined, size: 36),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selected!.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${_selected!.year ?? '年份未知'} · ${_selected!.genres.join(' / ')}',
                            style: WowType.body(12, color: WowColors.muted),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _selected!.overview.isEmpty
                                ? '此作品暂无中文简介'
                                : _selected!.overview,
                            maxLines: 8,
                            overflow: TextOverflow.ellipsis,
                            style: WowType.body(12, color: WowColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _replaceArt,
                  onChanged: _applying
                      ? null
                      : (v) => setState(() => _replaceArt = v!),
                  title: const Text(
                    '使用 TMDB 海报和剧照替换现有图片',
                    style: TextStyle(fontSize: 12),
                  ),
                  subtitle: const Text(
                    '关闭时优先保留本地或服务器图片，仅补充缺失图片',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: _applying
                      ? null
                      : () => setState(() => _selected = null),
                  child: const Text('返回匹配结果'),
                ),
              ],
              const SizedBox(height: 16),
              const TmdbCredit(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _applying ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected == null || _busy || _applying ? null : _apply,
          child: Text(_applying ? '正在保存…' : '确认匹配并保存'),
        ),
      ],
    ),
  );
}
