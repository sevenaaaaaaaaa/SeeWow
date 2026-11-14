import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/artwork.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import '../metadata/bangumi_client.dart';
import '../metadata/emby_metadata_client.dart';
import '../metadata/metadata_registry.dart';
import '../metadata/metadata_source.dart';
import '../metadata/tmdb_client.dart';
import '../metadata/tvmaze_client.dart';
import '../sources/native_bridge.dart';
import 'metadata_facts.dart';
import 'metadata_languages_view.dart';
import '../domain/metadata_languages.dart';

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
          style: TextStyle(
            color: WowColors.success,
            fontWeight: FontWeight.bold,
          ),
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
  final _token = TextEditingController(),
      _language = TextEditingController(text: 'zh-CN'),
      _region = TextEditingController(),
      _fallback = TextEditingController(text: 'en-US');
  bool _includeAdult = false;
  Set<String> _additional = MetadataLanguage.defaults.toSet();
  @override
  void initState() {
    super.initState();
    TmdbClient.readLocale().then((value) {
      if (!mounted) return;
      setState(() {
        _language.text = value.language;
        _region.text = value.region;
        _fallback.text = value.fallback;
        _includeAdult = value.includeAdult;
        _additional = value.additionalLanguages.toSet();
      });
    });
  }

  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    _token.dispose();
    _language.dispose();
    _region.dispose();
    _fallback.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TmdbClient.configure(
        _token.text,
        locale: MetadataLocale(
          language: _language.text.trim(),
          region: _region.text.trim().toUpperCase(),
          fallback: _fallback.text.trim(),
          includeAdult: _includeAdult,
          additionalLanguages: _additional.toList(),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : '保存失败，请检查配置后重试',
        );
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
                hintText: '保存到本机凭据存储；已有配置时留空保留',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _language,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '资料语言',
                hintText: 'zh-CN / zh-TW / en-US / ja-JP …',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _region,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '发行地区（可选）',
                hintText: 'CN / US / JP / KR …',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _fallback,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '缺失文字回退语言（留空关闭）',
                hintText: 'en-US',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _includeAdult,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _includeAdult = v ?? false),
              title: const Text('搜索包含成人分类的条目'),
            ),
            const SizedBox(height: 12),
            const Text('优先采集与展示的地区语言'),
            MetadataLanguagePicker(
              value: _additional,
              enabled: !_busy,
              onChanged: (value) => setState(() => _additional = value),
            ),
            const SizedBox(height: 12),
            const Text('资料覆盖和译名取决于服务。商用项目需另行确认 TMDB 数据与图片授权；自填 Token 不代替商用授权。'),
            const SizedBox(height: 16),
            const TmdbCredit(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: WowColors.error, fontSize: 12),
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
  final _language = TextEditingController(text: 'zh-CN'),
      _region = TextEditingController(),
      _year = TextEditingController();
  String _mediaType = 'movie';

  /// Which catalogue answers first. "auto" walks the whole chain, so a dead
  /// service or an unconfigured TMDB still returns something.
  String _sourceId = 'auto';
  bool _currentEpisode = false, _localeEdited = false;
  int _page = 1;
  bool _regionalSearch = false;
  TmdbClient? _tmdb;
  MetadataRegistry? _registry;
  String _sourcesSummary = '';
  String? _answeredBy;
  String? _tmdbUnavailable;
  List<MediaMetadata> _candidates = [];
  MediaMetadata? _selected;
  String? _error;
  bool _busy = false, _searched = false, _replaceArt = false, _applying = false;
  @override
  void initState() {
    super.initState();
    _mediaType = widget.item.kind == MediaKind.episode ? 'tv' : 'movie';
    _year.text = widget.item.kind == MediaKind.episode
        ? ''
        : widget.item.year?.toString() ?? '';
    TmdbClient.readLocale().then((value) {
      if (mounted && !_localeEdited)
        setState(() {
          _language.text = value.language;
          _region.text = value.region;
        });
    });
    _query = TextEditingController(
      text: widget.item.showTitle ?? widget.item.title,
    );
  }

  @override
  void dispose() {
    _registry?.close();
    _query.dispose();
    _language.dispose();
    _region.dispose();
    _year.dispose();
    super.dispose();
  }

  void _invalidate() {
    setState(() {
      _selected = null;
      _candidates = [];
      _searched = false;
      _answeredBy = null;
      _sourcesSummary = '';
    });
  }

  Future<void> _search({bool next = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      _selected = null;
    });
    try {
      final targetPage = next ? _page + 1 : 1;
      final year = _year.text.trim();
      if (year.isNotEmpty &&
          (int.tryParse(year) == null ||
              int.parse(year) < 1 ||
              int.parse(year) > 9999))
        throw const FormatException('年份需要为 1 到 9999');
      final parsedYear = year.isEmpty ? null : int.parse(year);
      final series = _mediaType == 'tv';
      final registry = await _buildRegistry();
      if (!mounted) return;
      _registry = registry;
      // Page 2 must ask the catalogue that answered page 1, or the list mixes
      // two catalogues' paging into one.
      final preferred = _sourceId != 'auto'
          ? _sourceId
          : (next ? _answeredBy : null);
      if (preferred != null) {
        final chosen = registry.byId(preferred);
        if (chosen == null) {
          throw FormatException(
            preferred == 'tvmaze'
                ? '这条记录没有对应的数据源；请改用「自动回退」，或先连接该服务器'
                : '数据源 $preferred 当前不可用',
          );
        }
        if (chosen.seriesOnly && !series) {
          throw const FormatException('TVmaze 只有剧集数据；电影请用 TMDB 或 Bangumi');
        }
      }
      List<MediaMetadata> results;
      if (_regionalSearch) {
        // Only TMDB can merge several languages in one lookup.
        final client = _tmdb;
        if (client == null) throw const FormatException('多语言合并搜索需要先配置 TMDB');
        results = [
          for (final item in await client.searchRegional(
            _query.text,
            series: series,
            year: parsedYear,
            page: targetPage,
          ))
            annotateFields(item, providerLabel(item.provider)),
        ];
        _sourcesSummary = 'TMDB 多语言合并 · ${results.length} 条';
      } else {
        final outcome = await registry.search(
          _query.text,
          series: series,
          year: parsedYear,
          page: targetPage,
          preferred: preferred,
          minimum: next ? 1 : 3,
        );
        results = outcome.results;
        _answeredBy = outcome.answeredBy ?? _answeredBy;
        _sourcesSummary = outcome.summary;
        if (_tmdbUnavailable != null && !_sourcesSummary.contains('TMDB')) {
          _sourcesSummary = '$_sourcesSummary · $_tmdbUnavailable';
        }
      }
      if (mounted)
        setState(() {
          _page = targetPage;
          _candidates = {
            for (final c in [if (next) ..._candidates, ...results])
              '${c.provider}:${c.mediaType}:${c.id}': c,
          }.values.toList();
          _searched = true;
        });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The picker lists "auto" plus whatever this library can actually reach.
  List<(String, String)> get _sourceChoices {
    final registry = _registry;
    if (registry == null) {
      return const [
        ('auto', '自动回退（多源合并）'),
        ('tmdb', 'TMDB（电影与剧集）'),
        ('tvmaze', 'TVmaze（仅剧集）'),
        ('bangumi', 'Bangumi（动画）'),
      ];
    }
    final choices = <(String, String)>[('auto', '自动回退（多源合并）')];
    for (final source in registry.sources) {
      choices.add((source.id, source.label));
    }
    if (!choices.any((choice) => choice.$1 == _sourceId)) {
      choices.add((_sourceId, _sourceId));
    }
    return choices;
  }

  /// Builds the catalogue chain for one search: TMDB when a key exists, the
  /// two keyless catalogues, and every connected Jellyfin/Emby server.
  Future<MetadataRegistry> _buildRegistry() async {
    _releaseClients();
    _tmdbUnavailable = null;
    final sources = <MetadataSource>[];
    try {
      final client = await (widget.clientFactory ?? TmdbClient.configured)();
      client.locale = MetadataLocale(
        language: _language.text.trim(),
        region: _region.text.trim().toUpperCase(),
        fallback: client.locale.fallback,
        includeAdult: client.locale.includeAdult,
        additionalLanguages: client.locale.additionalLanguages,
      );
      _tmdb = client;
      sources.add(client);
    } catch (error) {
      _tmdbUnavailable = 'TMDB 未配置（${_short(error)}）';
    }
    sources
      ..add(TvMazeClient())
      ..add(BangumiClient());
    for (final source in widget.library.sources) {
      if (!source.enabled) continue;
      if (source.kind != SourceKind.jellyfin &&
          source.kind != SourceKind.emby) {
        continue;
      }
      try {
        final token = await NativeBridge.secretRead(sourceSecretKey(source)) ?? '';
        if (token.trim().isEmpty) continue;
        sources.add(
          EmbyMetadataSource(
            base: Uri.parse(source.location),
            token: token.trim(),
            userId: source.username,
            kind: source.kind.name,
            serverName: source.name,
          ),
        );
      } catch (error) {
        debugPrint('跳过元数据服务器 ${source.name}: $error');
      }
    }
    return MetadataRegistry(sources);
  }

  void _releaseClients() {
    _registry?.close();
    _registry = null;
    _tmdb = null;
  }

  static String _short(Object error) {
    final text = error.toString();
    return text.startsWith('FormatException: ')
        ? text.substring('FormatException: '.length)
        : text;
  }

  Future<void> _preview(MediaMetadata candidate) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registry = _registry;
      if (registry == null) throw const FormatException('请先搜索一次再预览');
      // Episode-level lookup only exists on TMDB; every other catalogue answers
      // for the work as a whole and is completed from the other candidates.
      final episode =
          _tmdb != null &&
          _currentEpisode &&
          candidate.mediaType == 'tv' &&
          widget.item.season != null &&
          widget.item.episode != null;
      final match = episode
          ? annotateFields(
              await _tmdb!.episodeDetails(
                candidate,
                widget.item.season!,
                widget.item.episode!,
              ),
              providerLabel('tmdb'),
            )
          : await registry.details(
              candidate,
              supplements: _candidates,
            );
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
                onChanged: (_) => _invalidate(),
                decoration: InputDecoration(
                  labelText: '电影或剧集名称',
                  suffixIcon: IconButton(
                    tooltip: '搜索资料目录',
                    onPressed: _busy || _applying ? null : _search,
                    icon: const Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _sourceId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '数据源'),
                      items: [
                        for (final source in _sourceChoices)
                          DropdownMenuItem(
                            value: source.$1,
                            enabled:
                                source.$1 != 'tvmaze' || _mediaType == 'tv',
                            child: Text(
                              source.$2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy || _applying
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() {
                                _sourceId = value;
                                _invalidate();
                              });
                            },
                    ),
                  ),
                  Chip(label: Text(_mediaType == 'tv' ? '剧集／节目目录' : '电影／单片目录')),
                  SizedBox(
                    width: 130,
                    child: TextField(
                      controller: _language,
                      enabled: !_busy && !_applying,
                      onChanged: (_) {
                        _localeEdited = true;
                        _invalidate();
                      },
                      decoration: const InputDecoration(
                        labelText: '资料语言',
                        hintText: 'zh-CN',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _region,
                      enabled: !_busy && !_applying,
                      onChanged: (_) {
                        _localeEdited = true;
                        _invalidate();
                      },
                      decoration: const InputDecoration(
                        labelText: '发行地区',
                        hintText: 'CN',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _year,
                      enabled: !_busy && !_applying,
                      onChanged: (_) => _invalidate(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '年份'),
                    ),
                  ),
                ],
              ),
              if (_sourcesSummary.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '数据源：$_sourcesSummary',
                    style: WowType.body(11, color: WowColors.muted),
                  ),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _regionalSearch,
                onChanged: _busy || _applying
                    ? null
                    : (value) {
                        _regionalSearch = value ?? false;
                        _invalidate();
                      },
                title: const Text('按所选地区语言同时搜索'),
                subtitle: const Text('合并同一作品的 ID；当前仅查询资料目录，不获取播放源'),
              ),
              if (_tmdb != null && _tmdb!.regionalErrors.isNotEmpty)
                Text('部分语言查询未成功：${_tmdb!.regionalErrors.join(', ')}'),
              if (widget.item.kind == MediaKind.episode &&
                  widget.item.season != null &&
                  widget.item.episode != null &&
                  _mediaType == 'tv')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '匹配当前集 S${widget.item.season}E${widget.item.episode}',
                  ),
                  subtitle: const Text('关闭时匹配整部剧；特别篇可匹配第 0 季'),
                  value: _currentEpisode,
                  onChanged: _busy || _applying
                      ? null
                      : (v) => setState(() {
                          _currentEpisode = v;
                          _selected = null;
                        }),
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
                    style: TextStyle(fontSize: 12, color: WowColors.error),
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
                      '${c.year ?? '年份未知'} · ${providerLabel(c.provider)} ${c.id}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _preview(c),
                  ),
                if (_tmdb?.hasMore == true)
                  TextButton(
                    onPressed: _busy || _applying
                        ? null
                        : () => _search(next: true),
                    child: const Text('加载更多结果'),
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
                                ? '此作品暂缺所选语言的简介'
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
                MetadataFacts(metadata: _selected!, compact: true),
                if (_selected!.artworks.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('选择封面／背景图（语言为空表示无文字图）'),
                  SizedBox(
                    height: 130,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final art in _selected!.artworks)
                          SizedBox(
                            width: 100,
                            child: InkWell(
                              onTap: _applying
                                  ? null
                                  : () => setState(() {
                                      _selected = _selected!.withImages(
                                        poster: art.type == 'poster'
                                            ? art.url
                                            : null,
                                        backdrop: art.type == 'backdrop'
                                            ? art.url
                                            : null,
                                      );
                                      _replaceArt = true;
                                    }),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: WowArt(
                                      url: art.url,
                                      fallback: const Icon(
                                        Icons.image_outlined,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${art.type == 'poster' ? '封面' : '背景'} · ${art.language.isEmpty ? '无文字' : art.language}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _replaceArt,
                  onChanged: _applying
                      ? null
                      : (v) => setState(() => _replaceArt = v!),
                  title: const Text(
                    '使用数据源海报和剧照替换现有图片',
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
