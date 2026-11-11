import 'package:flutter/material.dart';

import '../domain/media_item.dart';
import '../metadata/subtitles.dart';

class DownloadedSubtitle {
  const DownloadedSubtitle(this.text, this.title, this.language);
  final String text, title, language;
}

Future<void> configureSubtitles(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _SubtitleConfig());
Future<DownloadedSubtitle?> findSubtitle(
  BuildContext context,
  MediaItem item, {
  Future<OpenSubtitlesClient> Function()? clientFactory,
}) => showDialog<DownloadedSubtitle>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _SubtitleSearch(item: item, clientFactory: clientFactory),
);

class _SubtitleConfig extends StatefulWidget {
  const _SubtitleConfig();
  @override
  State<_SubtitleConfig> createState() => _SubtitleConfigState();
}

class _SubtitleConfigState extends State<_SubtitleConfig> {
  final _key = TextEditingController(),
      _user = TextEditingController(),
      _password = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _key.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OpenSubtitlesClient.configure(
        _key.text,
        username: _user.text,
        password: _password.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : '配置或登录失败，请检查凭据、网络和服务额度',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('字幕服务配置'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '使用你自己的 OpenSubtitles API Key。账号登录可选，下载额度由服务和账号决定。商业应用需确认服务方案及字幕使用授权。',
              ),
              const SizedBox(height: 12),
              const SelectableText('https://www.opensubtitles.com/consumers'),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'OpenSubtitles API Key',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _user,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '用户名（可选）'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码（仅本次登录使用）'),
              ),
              const SizedBox(height: 12),
              const Text('密钥和登录会话单独保存。密码不写入片库；不会上传视频文件。会话失效时重新配置登录。'),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
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
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存字幕配置'),
        ),
      ],
    ),
  );
}

class _SubtitleSearch extends StatefulWidget {
  const _SubtitleSearch({required this.item, this.clientFactory});
  final MediaItem item;
  final Future<OpenSubtitlesClient> Function()? clientFactory;
  @override
  State<_SubtitleSearch> createState() => _SubtitleSearchState();
}

class _SubtitleSearchState extends State<_SubtitleSearch> {
  late final TextEditingController _query;
  final _languages = TextEditingController();
  OpenSubtitlesClient? _client;
  List<SubtitleCandidate> _results = [];
  String? _error;
  bool _busy = false, _searched = false;
  int _page = 1;
  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.item.libraryTitle);
  }

  @override
  void dispose() {
    _client?.close();
    _query.dispose();
    _languages.dispose();
    super.dispose();
  }

  void _invalidate() {
    setState(() {
      _results = [];
      _searched = false;
    });
  }

  Future<void> _search({bool next = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _client?.close();
      final client =
          await (widget.clientFactory ?? OpenSubtitlesClient.configured)();
      if (!mounted) {
        client.close();
        return;
      }
      _client = client;
      final targetPage = next ? _page + 1 : 1;
      final query = _query.text.trim();
      if (query.isEmpty) throw const FormatException('请填写标题或发行版本名称');
      final results = await client.search(
        widget.item,
        query: query == widget.item.libraryTitle ? null : query,
        languages: _languages.text.trim(),
        page: targetPage,
      );
      if (mounted)
        setState(() {
          _page = targetPage;
          _results = next ? [..._results, ...results] : results;
          _searched = true;
        });
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : '字幕搜索失败，请检查配置、网络或账号权限',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download(SubtitleCandidate result) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final text = await _client!.download(result);
      if (mounted)
        Navigator.pop(
          context,
          DownloadedSubtitle(text, result.filename, result.language),
        );
    } catch (_) {
      if (mounted) setState(() => _error = '下载失败，请检查账号额度、会话或选择其他字幕版本');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('搜索字幕'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '向 OpenSubtitles 发送标题或已匹配的 IMDb ID、季集和语言，不上传视频。按发行版本选择字幕，名称匹配不保证时间轴一致。',
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _query,
                enabled: !_busy,
                onChanged: (_) => _invalidate(),
                decoration: const InputDecoration(labelText: '标题或发行版本名称'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _languages,
                enabled: !_busy,
                onChanged: (_) => _invalidate(),
                decoration: const InputDecoration(
                  labelText: '字幕语言（留空搜索全部语言）',
                  hintText: 'zh-cn,zh-tw,en,ja,ko,pt-br …',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _search(),
                    icon: const Icon(Icons.search),
                    label: const Text('查找字幕'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => configureSubtitles(context),
                    child: const Text('配置字幕服务'),
                  ),
                ],
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_searched && _results.isEmpty && !_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('暂无匹配字幕。可以更换原始标题、语言或手动导入本地字幕。'),
                ),
              for (final result in _results)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  enabled: !_busy,
                  title: Text(result.filename),
                  subtitle: Text(
                    [
                      result.language,
                      result.release,
                      if (result.hearingImpaired) '听障字幕',
                      if (result.machineTranslated) '机器翻译',
                      '${result.downloads} 次下载',
                    ].where((s) => s.isNotEmpty).join(' · '),
                  ),
                  trailing: const Icon(Icons.download_outlined),
                  onTap: () => _download(result),
                ),
              if (_client?.hasMore == true)
                TextButton(
                  onPressed: _busy ? null : () => _search(next: true),
                  child: const Text('更多字幕版本'),
                ),
              const SizedBox(height: 12),
              const Text('字幕资料来源：OpenSubtitles。仅下载并加载你有权使用的字幕，本次加载不改写媒体文件。'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
