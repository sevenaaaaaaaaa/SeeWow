import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../agent/agent_controller.dart';
import 'subscription_dialog.dart';
import '../data/iptv_store.dart';
import '../data/library_store.dart';
import '../design/cinema_widgets.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../domain/source_catalog.dart';
import '../sources/remote_files.dart';
import '../sources/native_bridge.dart';
import '../sources/plex_login.dart';
import '../sources/smb_mounter.dart';

/// Android 13+ scoped storage needs an explicit media grant before the raw
/// path returned by the folder picker can be listed.
Future<void> _requestAndroidMediaAccess() async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('seewow/native')
        .invokeMethod<bool>('media.request');
  } catch (_) {
    // The system picker grant still applies where the plugin is unavailable.
  }
}

List<SourceKind> _availableModes(List<SourceKind> modes) {
  final filtered = modes
      .where(
        (m) => m != SourceKind.smb || !(Platform.isIOS || Platform.isAndroid),
      )
      .toList();
  // Providers that only expose SMB still need a selectable mode so the picker
  // does not throw on mobile; the dialog then explains the limitation.
  return filtered.isEmpty ? modes : filtered;
}

String sourceDisplayAddress(String location) {
  final uri = Uri.tryParse(location);
  if (uri == null || uri.host.isEmpty) return location;
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}${uri.hasQuery ? '?…' : ''}';
}

Future<void> connectSource(
  BuildContext context,
  LibraryStore library,
  IPTVStore iptv, {
  String initial = '',
  String type = 'webdav',
  String providerId = '',
  MediaSource? existing,
}) async {
  if (existing?.kind == SourceKind.local) {
    await connectLocalMediaFolder(
      context,
      library,
      providerId: existing!.providerId,
      existing: existing,
    );
    return;
  }
  if (type == 'iptv' ||
      RegExp(r'\.m3u8?(\?|$)', caseSensitive: false).hasMatch(initial)) {
    await importSubscription(context, iptv, initial: initial);
    return;
  }
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConnectDialog(
      library: library,
      iptv: iptv,
      initial: existing?.location ?? initial,
      initialType:
          existing?.kind.name ??
          (initial.startsWith('smb://')
              ? 'smb'
              : RegExp(r'\.m3u8?(\?|$)', caseSensitive: false).hasMatch(initial)
              ? 'iptv'
              : type),
      providerId: existing?.providerId ?? providerId,
      existing: existing,
    ),
  );
}

Future<void> chooseSourceProvider(
  BuildContext context,
  LibraryStore library,
  IPTVStore iptv,
) async {
  final provider = await showDialog<SourceProvider>(
    context: context,
    builder: (_) => const _ProviderPicker(),
  );
  if (provider == null || !context.mounted) return;
  if (provider.modes.first == SourceKind.local) {
    await connectLocalMediaFolder(context, library, providerId: provider.id);
    return;
  }
  await connectSource(
    context,
    library,
    iptv,
    providerId: provider.id,
    type: _availableModes(provider.modes).first.name,
  );
}

Future<void> connectLocalMediaFolder(
  BuildContext context,
  LibraryStore library, {
  String providerId = '',
  MediaSource? existing,
  Future<String?> Function()? pickDirectory,
}) async {
  try {
    await _requestAndroidMediaAccess();
    final path = await (pickDirectory != null
        ? pickDirectory()
        : Platform.isIOS
        ? NativeBridge.pickIOSFolder()
        : FilePicker.getDirectoryPath(
            dialogTitle: providerId == 'telegramLocal'
                ? '选择 Telegram 已下载的媒体目录'
                : '选择媒体库文件夹',
          ));
    if (path == null) return;
    final previous =
        existing ??
        library.sources
            .where((s) => s.kind == SourceKind.local && s.location == path)
            .firstOrNull;
    final effectiveProvider = previous?.providerId == 'telegramLocal'
        ? 'telegramLocal'
        : providerId;
    final segments = path
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();
    final label = segments.isEmpty ? path : segments.last;
    final source = MediaSource(
      id: previous?.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}',
      kind: SourceKind.local,
      providerId: effectiveProvider,
      name: effectiveProvider == 'telegramLocal' ? 'Telegram · $label' : label,
      location: path,
      enabled: previous?.enabled ?? true,
    );
    if (previous == null) {
      await library.addSource(source);
    } else {
      await library.updateSource(source);
    }
    final scanError = library.sourceErrors[source.id];
    if (scanError != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('目录扫描失败：$scanError（已保留原有条目）'),
          duration: const Duration(seconds: 8),
        ),
      );
    }
  } catch (e) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('未能打开文件夹：$e'),
          duration: const Duration(seconds: 8),
        ),
      );
  }
}

class _ProviderPicker extends StatefulWidget {
  const _ProviderPicker();
  @override
  State<_ProviderPicker> createState() => _ProviderPickerState();
}

class _ProviderPickerState extends State<_ProviderPicker> {
  final _query = TextEditingController();
  String _category = '全部';
  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = sourceProviders
        .where(
          (p) =>
              (_category == '全部' || p.category == _category) &&
              '${p.name} ${p.id}'.toLowerCase().contains(
                _query.text.trim().toLowerCase(),
              ),
        )
        .toList();
    return AlertDialog(
      title: const Text('选择你的服务'),
      content: SizedBox(
        width: 600,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '飞牛、群晖、Plex、夸克、115…',
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final category in [
                    '全部',
                    'NAS',
                    '媒体服务器',
                    '网盘',
                    '音乐服务器',
                    '本地媒体',
                    '通用',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  for (final p in providers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        p.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${p.category} · ${p.modes.contains(SourceKind.openlist) && p.category == '网盘' ? '通过 OpenList / Alist，原生授权待接' : sourceModeLabel(_availableModes(p.modes).first)}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }
}

class SourcesView extends StatefulWidget {
  const SourcesView({
    super.key,
    required this.store,
    required this.iptv,
    required this.onAgent,
  });
  final LibraryStore store;
  final IPTVStore iptv;
  final ValueChanged<String> onAgent;
  @override
  State<SourcesView> createState() => _SourcesViewState();
}

class _SourcesViewState extends State<SourcesView> {
  final _links = TextEditingController();
  bool _folderBusy = false;
  @override
  void dispose() {
    _links.dispose();
    super.dispose();
  }

  Future<void> _folder({String providerId = ''}) async {
    setState(() => _folderBusy = true);
    try {
      await connectLocalMediaFolder(
        context,
        widget.store,
        providerId: providerId,
      );
    } finally {
      if (mounted) setState(() => _folderBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.store, widget.iptv]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) {
        final store = widget.store;
        final urls = SourceDiscovery.extract(_links.text);
        return ListView(
          padding: EdgeInsets.all(box.maxWidth < 700 ? 20 : 32),
          children: [
            const PageIntro(
              eyebrow: 'ONE LIBRARY. EVERYWHERE.',
              title: '让片源，汇聚于此。',
              description: '本地、NAS、网盘和直播订阅，各有入口，最终回到同一个影院。',
            ),
            const SizedBox(height: 26),
            Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                _entry(
                  box,
                  Icons.folder_outlined,
                  '本地文件夹',
                  '选择目录，递归扫描电影与剧集',
                  _folderBusy ? null : _folder,
                ),
                _entry(
                  box,
                  Icons.dns_outlined,
                  '飞牛 / 群晖 NAS',
                  Platform.isIOS || Platform.isAndroid
                      ? '通过 WebDAV / File Station / OpenList 接入'
                      : '连接共享目录 · 桌面系统挂载',
                  () => chooseSourceProvider(context, store, widget.iptv),
                ),
                _entry(
                  box,
                  Icons.cloud_outlined,
                  '网盘 / WebDAV',
                  '通过 Alist / OpenList 等网关接入',
                  () => connectSource(context, store, widget.iptv),
                ),
                _entry(
                  box,
                  Icons.movie_filter_outlined,
                  'Jellyfin / Emby',
                  '同步媒体库、海报与直接播放地址',
                  () => connectSource(
                    context,
                    store,
                    widget.iptv,
                    type: 'jellyfin',
                  ),
                ),
                _entry(
                  box,
                  Icons.video_library_outlined,
                  'Plex',
                  '账号登录 · 自动选择服务器与原文件播放',
                  () => connectSource(
                    context,
                    store,
                    widget.iptv,
                    type: 'plex',
                    providerId: 'plex',
                  ),
                ),
                _entry(
                  box,
                  Icons.folder_special_outlined,
                  'Telegram 本地媒体',
                  '选择已下载目录 · 不连接账号、不发送给 AI',
                  _folderBusy
                      ? null
                      : () => _folder(providerId: 'telegramLocal'),
                ),
                _entry(
                  box,
                  Icons.rss_feed_rounded,
                  '直播订阅',
                  'M3U / TXT / JSON · 先预览再导入',
                  () =>
                      connectSource(context, store, widget.iptv, type: 'iptv'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () =>
                      chooseSourceProvider(context, store, widget.iptv),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('选择网盘、NAS 或音乐服务'),
                ),
                OutlinedButton.icon(
                  onPressed: () => connectSource(
                    context,
                    store,
                    widget.iptv,
                    type: 'navidrome',
                    providerId: 'navidrome',
                  ),
                  icon: const Icon(Icons.library_music_outlined, size: 18),
                  label: const Text('Navidrome 音乐库'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            CinemaPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(
                    '把链接交给 Agent',
                    subtitle: '粘贴订阅地址或包含订阅链接的网页。Agent 可读取页面、收集候选，再由你连接。',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _links,
                    onChanged: (_) => setState(() {}),
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: '粘贴 http(s)://… 或 smb://…，支持一次粘贴多个链接',
                      labelText: '待收集的地址',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: urls.isEmpty
                            ? null
                            : () => widget.onAgent(_links.text),
                        icon: const Icon(Icons.auto_awesome, size: 17),
                        label: const Text('解析并收集候选'),
                      ),
                      Text(
                        '已识别 ${urls.length} 个地址 · 不自动导入',
                        style: TextStyle(fontSize: 12, color: WowColors.muted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SectionTitle(
              '已添加的媒体来源',
              subtitle: '${store.sources.length} 个来源 · 扫描失败保留原片库',
            ),
            const SizedBox(height: 16),
            if (store.sources.isEmpty)
              const CinemaPanel(
                child: Text(
                  '还没有添加媒体来源。选择上方任一入口开始。',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            for (final s in store.sources)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CinemaPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            s.kind == SourceKind.local
                                ? Icons.folder_outlined
                                : s.kind == SourceKind.smb
                                ? Icons.dns_outlined
                                : Icons.cloud_outlined,
                            size: 24,
                            color: WowColors.accent,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${providerById(s.providerId)?.name ?? sourceModeLabel(s.kind)} · ${store.items.where((i) => i.sourceId == s.id).length} 个条目',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: WowColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (store.scanningIds.contains(s.id))
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            IconButton(
                              tooltip: '重新扫描 ${s.name}',
                              onPressed: () => store.rescan(s),
                              icon: const Icon(Icons.sync, size: 20),
                            ),
                          PopupMenuButton<String>(
                            tooltip: '片源操作',
                            onSelected: (action) => action == 'edit'
                                ? connectSource(
                                    context,
                                    store,
                                    widget.iptv,
                                    existing: s,
                                  )
                                : _remove(s),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('编辑连接与凭据'),
                              ),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('断开来源（不删除文件）'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        '${sourceDisplayAddress(s.location)}${s.rootPath == '/' ? '' : ' · ${s.rootPath}'}',
                        style: TextStyle(fontSize: 11, color: WowColors.muted),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            store.sourceErrors.containsKey(s.id)
                                ? Icons.error_outline
                                : s.lastScan == null
                                ? Icons.circle_outlined
                                : Icons.check_circle_outline,
                            size: 14,
                            color: store.sourceErrors.containsKey(s.id)
                                ? WowColors.error
                                : WowColors.success,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              store.sourceErrors[s.id] ??
                                  (s.lastScan == null
                                      ? '尚未完成首次扫描'
                                      : '上次扫描成功 · ${_date(s.lastScan!)}'),
                              style: TextStyle(
                                fontSize: 11,
                                color: store.sourceErrors.containsKey(s.id)
                                    ? WowColors.error
                                    : WowColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SectionTitle(
              '直播订阅',
              subtitle:
                  '${widget.iptv.playlists.length} 个订阅 · ${widget.iptv.channels.length} 个频道',
            ),
            const SizedBox(height: 16),
            for (final p in widget.iptv.playlists)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: CinemaPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.rss_feed, color: WowColors.accent),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${p.channelCount} 个频道 · ${p.epgCount} 条节目',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: WowColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '刷新订阅',
                            onPressed: widget.iptv.loading
                                ? null
                                : () => widget.iptv.reload(p),
                            icon: const Icon(Icons.sync),
                          ),
                          PopupMenuButton<String>(
                            tooltip: '订阅操作',
                            onSelected: (_) => widget.iptv.removePlaylist(p),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('移除订阅'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        sourceDisplayAddress(p.source),
                        style: TextStyle(fontSize: 11, color: WowColors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            if (widget.iptv.toast != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.iptv.toast!,
                  style: TextStyle(fontSize: 12, color: WowColors.muted),
                ),
              ),
            const SizedBox(height: 28),
            Text(
              '网盘需要提供可用的 WebDAV 网关地址；尚不支持网盘原生 OAuth。国内云盘通过已配置对应驱动的 OpenList / Alist 读取；Plex、群晖 File Station 与 Navidrome 有独立适配。飞牛影视专有接口与局域网自动发现仍待接入。',
              style: WowType.body(12, color: WowColors.muted),
            ),
          ],
        );
      },
    ),
  );
  Widget _entry(
    BoxConstraints box,
    IconData icon,
    String title,
    String detail,
    VoidCallback? onTap,
  ) {
    final count = box.maxWidth > 1100
        ? 3
        : box.maxWidth > 550
        ? 2
        : 1;
    final pad = box.maxWidth < 700 ? 20.0 : 32.0;
    return SizedBox(
      width: (box.maxWidth - pad * 2 - (count - 1) * 14) / count,
      child: Material(
        color: WowColors.panel,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 150,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border.all(color: WowColors.line),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: WowColors.accent, size: 25),
                    const Spacer(),
                    Icon(Icons.add, size: 18, color: WowColors.muted),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  detail,
                  maxLines: 2,
                  style: TextStyle(fontSize: 11, color: WowColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _remove(MediaSource s) async {
    await widget.store.removeSource(s);
    await NativeBridge.secretDelete(sourceSecretKey(s));
  }

  String _date(DateTime d) =>
      '${d.month}/${d.day} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({
    required this.library,
    required this.iptv,
    required this.initial,
    required this.initialType,
    required this.providerId,
    this.existing,
  });
  final LibraryStore library;
  final IPTVStore iptv;
  final String initial, initialType, providerId;
  final MediaSource? existing;
  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late String _type;
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _user = TextEditingController(),
      _password = TextEditingController(),
      _epg = TextEditingController();
  late final TextEditingController _location, _root;
  String? _error;
  bool _busy = false;
  PlexLogin? _plexLogin;
  PlexPin? _plexPin;
  String? _plexStatus;
  bool _plexBusy = false;
  int _plexSession = 0;
  SourceProvider? get _provider => providerById(widget.providerId);
  SourceKind get _kind => SourceKind.values.firstWhere(
    (k) => k.name == _type,
    orElse: () => SourceKind.webdav,
  );
  bool get _server => ['jellyfin', 'emby'].contains(_type);
  bool get _rooted => ['openlist', 'synology'].contains(_type);
  bool get _userVisible => [
    'smb',
    'webdav',
    'synology',
    'navidrome',
    'jellyfin',
    'emby',
  ].contains(_type);
  bool get _passwordRequired =>
      ['synology', 'navidrome', 'plex', 'jellyfin', 'emby'].contains(_type);
  String get _secretLabel => switch (_type) {
    'plex' => 'Plex Token',
    'openlist' => 'OpenList / Alist Token（允许匿名时可留空）',
    'jellyfin' || 'emby' => 'API Key（单独保存，不发给 AI）',
    _ => '密码（单独保存，不发给 AI）',
  };
  String get _hint => switch (_type) {
    'smb' => 'smb://192.168.1.10/Movies',
    'openlist' => 'http://192.168.1.10:5244',
    'synology' => 'https://192.168.1.10:5001',
    'plex' => 'http://192.168.1.10:32400',
    'navidrome' => 'http://192.168.1.10:4533',
    'iptv' => 'https://example.com/channels.m3u',
    _ => 'https://example.com/dav/',
  };
  String get _guidance => switch (_type) {
    'smb' => '填写共享地址即可，192.168.1.10/媒体 或 smb://192.168.1.10/媒体 都行。飞牛、群晖均可通过共享目录接入；SMB 目前支持桌面系统。',
    'webdav' => '填写实际 WebDAV 地址。网盘可使用网关的 /dav/ 路径，NAS 需要先启用 WebDAV 服务。',
    'openlist' => '填写网关服务地址与挂载根目录，不是网盘分享链接。需要先在 OpenList / Alist 配好对应驱动。播放前重新获取直链，Token 不会发给云盘直链站点。',
    'synology' =>
      '群晖 File Station 只读接入。填写 DSM 服务根地址与共享文件夹路径。需要二步验证的账号可先使用 SMB / WebDAV。',
    'navidrome' =>
      'Navidrome 是音乐服务器，导入曲目到音乐库。通过 OpenSubsonic 认证，密码不存入播放地址，播放时生成认证参数。',
    'plex' => '优先用 Plex 账号登录：应用会显示 plex.tv/link 验证码，登录后自动列出你的服务器。也可以继续手动填写服务器地址与 Token。电影与剧集保留服务端海报和简介，直接播放原文件，不请求转码。',
    'jellyfin' ||
    'emby' => '使用服务器 API Key。地址包含反向代理子路径；用户 ID 可选。读取片库与原文件流，不向服务器回写观看状态。',
    _ => '支持 M3U / TXT / JSON 纯数据列表；先预览，不执行远程插件。',
  };
  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _location = TextEditingController(text: widget.initial);
    _root = TextEditingController(text: widget.existing?.rootPath ?? '/');
    _name.text = widget.existing?.name ?? _provider?.name ?? '';
    _user.text = widget.existing?.username ?? '';
  }

  @override
  void dispose() {
    _plexSession++;
    for (final c in [_name, _user, _password, _epg, _location, _root]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _plexSignIn() async {
    final session = ++_plexSession;
    setState(() {
      _plexBusy = true;
      _plexStatus = '正在向 plex.tv 申请登录验证码…';
    });
    try {
      final login = _plexLogin ??= await PlexLogin.create();
      final pin = await login.createPin();
      if (!mounted || session != _plexSession) return;
      setState(() {
        _plexPin = pin;
        _plexStatus = '在浏览器打开 plex.tv/link，输入验证码 ${pin.code}';
      });
      await _openPlexLink();
      String? token;
      for (var attempt = 0; attempt < 150; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted || session != _plexSession) return;
        token = await login.pollToken(pin.id);
        if (token != null) break;
      }
      if (!mounted || session != _plexSession) return;
      if (token == null) {
        setState(() => _plexStatus = '登录超时，请重新点击登录');
        return;
      }
      setState(() => _plexStatus = '已登录，正在读取 Plex 服务器…');
      final servers = await login.servers(token);
      if (!mounted || session != _plexSession) return;
      if (servers.isEmpty) {
        setState(() => _plexStatus = '该账号下没有可用的 Plex 服务器');
        return;
      }
      final chosen = servers.length == 1
          ? servers.first
          : await _choosePlexServer(servers);
      if (!mounted || session != _plexSession) return;
      if (chosen == null) {
        setState(() => _plexStatus = '已登录，未选择服务器');
        return;
      }
      setState(() {
        _location.text = chosen.uri;
        _name.text = chosen.name;
        _password.text = chosen.token;
        _plexStatus = '已登录：${chosen.name}';
      });
      await _connect();
    } on PlexException catch (e) {
      if (mounted && session == _plexSession)
        setState(() => _plexStatus = '登录失败：${e.message}');
    } catch (e) {
      if (mounted && session == _plexSession)
        setState(() => _plexStatus = '登录失败：$e');
    } finally {
      if (mounted && session == _plexSession) setState(() => _plexBusy = false);
    }
  }

  Future<PlexServer?> _choosePlexServer(List<PlexServer> servers) =>
      showDialog<PlexServer>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('选择 Plex 服务器'),
          children: [
            for (final server in servers)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, server),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.name, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 3),
                    Text(
                      server.uri,
                      style: TextStyle(fontSize: 11, color: WowColors.muted),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Future<void> _openPlexLink() async {
    try {
      await launchUrl(
        Uri.parse('https://plex.tv/link'),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // The code stays visible and copyable if no browser is available.
    }
  }

  Future<void> _connect() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var location = _location.text.trim();
      if (_type == 'smb') location = SmbMounter.normalizeSmbLocation(location);
      if (_type == 'iptv') {
        if (!await importSubscription(
          context,
          widget.iptv,
          initial: location,
          name: _name.text.trim(),
          epgUrl: _epg.text.trim(),
        ))
          return;
      } else {
        final root = _rooted ? normalizedRemotePath(_root.text) : '/';
        final previous =
            widget.existing ??
            widget.library.sources
                .where(
                  (s) =>
                      s.location == location &&
                      s.rootPath == root &&
                      s.kind == _kind,
                )
                .firstOrNull;
        final source = MediaSource(
          id: previous?.id ?? 'net-${DateTime.now().microsecondsSinceEpoch}',
          kind: _kind,
          name: _name.text.trim().isEmpty
              ? (_provider?.name ?? Uri.parse(location).host)
              : _name.text.trim(),
          location: location,
          username: _userVisible ? _user.text.trim() : '',
          rootPath: root,
          providerId: widget.providerId,
          enabled: previous?.enabled ?? true,
          lastScan: previous?.lastScan,
        );
        if (_password.text.isNotEmpty)
          await NativeBridge.secretWrite(
            sourceSecretKey(source),
            _password.text,
          );
        if (previous == null) {
          await widget.library.addSource(source);
        } else {
          await widget.library.updateSource(source);
        }
        final error = widget.library.sourceErrors[source.id];
        if (error != null) throw StateError(error);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modes = _availableModes(
      _provider?.modes ??
          [
            SourceKind.smb,
            SourceKind.webdav,
            SourceKind.jellyfin,
            SourceKind.emby,
            SourceKind.plex,
            SourceKind.openlist,
            SourceKind.synology,
            SourceKind.navidrome,
            SourceKind.iptv,
          ],
    );
    if (_type == 'smb' && !modes.contains(SourceKind.smb))
      modes.add(SourceKind.smb);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(widget.existing != null ? '编辑连接' : '连接你的片源'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_provider != null) ...[
                    Text(
                      _provider!.name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _provider!.description,
                      style: WowType.body(12, color: WowColors.muted),
                    ),
                    const SizedBox(height: 16),
                  ],
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: const InputDecoration(labelText: '片源类型 / 接入方式'),
                    isExpanded: true,
                    items: [
                      for (final mode in modes)
                        DropdownMenuItem(
                          value: mode.name,
                          child: Text(
                            sourceModeLabel(mode),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                    onChanged: _busy || widget.existing != null
                        ? null
                        : (v) => setState(() {
                            _type = v!;
                            _error = null;
                          }),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _guidance,
                    style: WowType.body(12, color: WowColors.muted),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    decoration: const InputDecoration(labelText: '显示名称（可选）'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _location,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: '地址',
                      hintText: _hint,
                    ),
                    validator: (value) {
                      if (_type == 'smb') {
                        try {
                          SmbMounter.normalizeSmbLocation(value ?? '');
                        } on NativeException catch (e) {
                          return e.message;
                        }
                        if (!(Platform.isMacOS ||
                            Platform.isWindows ||
                            Platform.isLinux))
                          return '移动端 SMB 暂未接入，请使用 WebDAV';
                        return null;
                      }
                      final uri = Uri.tryParse(value?.trim() ?? '');
                      if (uri == null ||
                          uri.host.isEmpty ||
                          uri.userInfo.isNotEmpty)
                        return '填写完整地址，账号和密钥填在单独字段';
                      if (!['http', 'https'].contains(uri.scheme)) {
                        return '需要 http:// 或 https:// 地址';
                      }
                      if (_type != 'iptv' && (uri.hasQuery || uri.hasFragment))
                        return '地址中不要包含查询参数或密钥';
                      return null;
                    },
                  ),
                  if (_type == 'plex') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _busy || _plexBusy ? null : _plexSignIn,
                          icon: _plexBusy
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.login, size: 16),
                          label: Text(
                            _plexPin == null ? '使用 Plex 账号登录' : '重新获取验证码',
                          ),
                        ),
                        if (_plexPin != null && !_plexBusy) ...[
                          Text(
                            'plex.tv/link · ${_plexPin!.code}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          IconButton(
                            tooltip: '复制验证码',
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: _plexPin!.code),
                              );
                              if (mounted)
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('验证码已复制')),
                                );
                            },
                            icon: const Icon(Icons.copy, size: 16),
                          ),
                          TextButton(
                            onPressed: _openPlexLink,
                            child: const Text('打开 plex.tv/link'),
                          ),
                        ],
                      ],
                    ),
                    if (_plexStatus != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _plexStatus!,
                          style: TextStyle(
                            fontSize: 12,
                            color: WowColors.muted,
                          ),
                        ),
                      ),
                  ],
                  if (_rooted) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _root,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: _type == 'openlist' ? '网关挂载根目录' : '共享文件夹路径',
                        hintText: _type == 'openlist' ? '/夸克/电影' : '/video',
                      ),
                      validator: (v) {
                        try {
                          normalizedRemotePath(v ?? '');
                          return null;
                        } catch (_) {
                          return '目录不能包含 ..';
                        }
                      },
                    ),
                  ],
                  if (_userVisible) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _user,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: _server ? '用户 ID（可选）' : '用户名',
                      ),
                      validator: (v) =>
                          ['synology', 'navidrome'].contains(_type) &&
                              (v == null || v.trim().isEmpty)
                          ? '请填写用户名'
                          : null,
                    ),
                  ],
                  if (_type != 'iptv') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      enabled: !_busy,
                      decoration: InputDecoration(
                        labelText: _secretLabel,
                        hintText: widget.existing == null
                            ? null
                            : '留空保留当前地址的凭据',
                      ),
                      validator: (v) {
                        final required =
                            _passwordRequired && widget.existing == null ||
                            widget.existing != null &&
                                _location.text.trim() !=
                                    widget.existing!.location;
                        if (required && (v == null || v.isEmpty))
                          return _server
                              ? '请输入服务器 API Key'
                              : '请填写凭据；更换地址时不自动复用旧密钥';
                        return null;
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _epg,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'XMLTV 节目单地址（可选）',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final u = Uri.tryParse(v.trim());
                        return u != null &&
                                ['http', 'https'].contains(u.scheme) &&
                                u.host.isNotEmpty &&
                                u.userInfo.isEmpty
                            ? null
                            : '请填写有效的 http(s) 地址';
                      },
                    ),
                  ],
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: LinearProgressIndicator(),
                    ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        '连接失败：$_error',
                        style: TextStyle(color: WowColors.error, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _busy ? null : _connect,
            child: Text(_busy ? '正在测试并扫描…' : '测试连接并导入'),
          ),
        ],
      ),
    );
  }
}
