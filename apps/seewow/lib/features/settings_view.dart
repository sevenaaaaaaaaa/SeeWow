import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/pressable.dart';
import '../design/skin.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import '../sources/native_bridge.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.store});
  final LibraryStore store;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  @override
  void initState() {
    super.initState();
    if (Platform.environment['SEEWOW_OPEN_DIALOG'] == 'network') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _addNetwork());
    }
  }

  bool _hwDecode = true;
  bool _autoScan = true;
  bool _busy = false;

  Future<void> _addFolder() async {
    final path = await FilePicker.getDirectoryPath(dialogTitle: '选择片库文件夹');
    if (path == null) return;
    setState(() => _busy = true);
    final name = path.split(Platform.pathSeparator).where((p) => p.isNotEmpty).last;
    await widget.store.addSource(MediaSource(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      kind: SourceKind.local,
      name: name,
      location: path,
      lastScan: DateTime.now(),
    ));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _rescan(MediaSource source) async {
    setState(() => _busy = true);
    await widget.store.rescan(source);
    if (mounted) setState(() => _busy = false);
  }


  Future<void> _addNetwork() async {
    final result = await showDialog<_NetworkSourceResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.66),
      builder: (_) => const _NetworkSourceDialog(),
    );
    if (result == null) return;
    setState(() => _busy = true);
    final source = MediaSource(
      id: 'net-' + DateTime.now().millisecondsSinceEpoch.toString(),
      kind: result.kind,
      name: result.name,
      location: result.location,
      username: result.username,
    );
    try {
      if (result.password.isNotEmpty) {
        await NativeBridge.secretWrite(sourceSecretKey(source), result.password);
      }
      await widget.store.addSource(source);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('连接失败：' + (e is NativeException ? e.message : e.toString())),
          backgroundColor: WowColors.panel,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(MediaSource source) async {
    await NativeBridge.secretDelete(sourceSecretKey(source));
    await widget.store.removeSource(source);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final gutter = WowSpace.gutter(MediaQuery.sizeOf(context).width);
    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 80),
      children: [
        Row(children: [
          Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: WowColors.accent.withValues(alpha: 0.9))),
          const SizedBox(width: 10),
          Text('PREFERENCES', style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.34), spacing: 2.4)),
        ]),
        const SizedBox(height: 18),
        Text('设置', style: WowType.display(46, FontWeight.w400, spacing: -1.2, height: 1.0)),
        const SizedBox(height: 12),
        Text('SOURCES  ·  PLAYBACK  ·  ABOUT', style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.3), spacing: 2.6)),
        const SizedBox(height: 14),
        Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
        const SizedBox(height: 30),
        _Card(
          index: 1,
          title: '外观',
          subtitle: '配色 · 强调色 · 字体 · 背景 · 海报占位',
          children: [
            _ChoiceRow(label: '配色', options: [
              for (final v in WowPaletteId.values)
                (wowPaletteLabel(v), WowSkin.I.paletteId == v, () => WowSkin.I.apply(palette: v)),
            ]),
            _ChoiceRow(label: '强调色', options: [
              for (final v in WowAccentId.values)
                (wowAccentLabel(v), WowSkin.I.accentId == v, () => WowSkin.I.apply(accent: v)),
            ]),
            _ChoiceRow(label: '字体', options: [
              for (final v in WowFontId.values)
                (wowFontLabel(v), WowSkin.I.fontId == v, () => WowSkin.I.apply(font: v)),
            ]),
            _ChoiceRow(label: '背景', options: [
              for (final v in WowBackdropId.values)
                (wowBackdropLabel(v), WowSkin.I.backdropId == v, () => WowSkin.I.apply(backdrop: v)),
            ]),
            _ChoiceRow(label: '海报占位', options: [
              for (final v in WowPosterId.values)
                (wowPosterLabel(v), WowSkin.I.posterId == v, () => WowSkin.I.apply(poster: v)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Text('切换立刻生效，自动记住。', style: WowType.monoLabel(9, color: WowColors.faint, spacing: 0.4)),
              const Spacer(),
              _MiniButton(label: '恢复默认', onTap: WowSkin.I.reset),
            ]),
          ],
        ),
        const SizedBox(height: 18),
        _Card(
          index: 2,
          title: '片源',
          subtitle: '本地文件夹、NAS、WebDAV、Emby / Jellyfin / Plex、DLNA',
          children: [
            for (final s in store.sources)
              _SourceRow(
                source: s,
                busy: _busy,
                onRescan: () => _rescan(s),
                onRemove: () => _remove(s),
              ),
            if (store.sources.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('还没有片源。添加一个文件夹开始。', style: WowType.body(12.5, color: WowColors.muted)),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _AddButton(
                  icon: Icons.create_new_folder_outlined,
                  label: _busy ? '正在扫描…' : '添加文件夹',
                  onTap: _busy ? null : _addFolder,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AddButton(
                  icon: Icons.lan_outlined,
                  label: '添加网络位置',
                  onTap: _busy ? null : _addNetwork,
                ),
              ),
            ]),
          ],
        ),
        const SizedBox(height: 18),
        _Card(
          index: 3,
          title: '播放',
          subtitle: 'media_kit + libmpv 内核，HDR 由系统原生管线接管',
          children: [
            _ToggleRow(title: '硬件解码', detail: '优先交给 GPU 解码，降低 4K 功耗', value: _hwDecode, onChanged: (v) => setState(() => _hwDecode = v)),
            _ToggleRow(title: '启动时自动扫描', detail: '打开 App 后刷新所有片源', value: _autoScan, onChanged: (v) => setState(() => _autoScan = v)),
            const _InfoRow(label: '内核', value: 'libmpv · MEDIA_KIT'),
          ],
        ),
        const SizedBox(height: 18),
        _Card(
          index: 4,
          title: '关于',
          subtitle: 'SeeWow 1.0 · Cinema for every screen',
          children: const [
            _InfoRow(label: '版本', value: '1.0.0'),
            _InfoRow(label: '平台', value: 'macOS · Windows · Linux · iPadOS · Android'),
          ],
        ),
      ],
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.options});
  final String label;
  final List<(String, bool, VoidCallback)> options;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 84,
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(label, style: WowType.monoLabel(9.5, color: WowColors.faint, spacing: 1.6)),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (title, selected, onTap) in options)
                _Chip(label: title, selected: selected, onTap: onTap),
            ],
          ),
        ),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? WowColors.accent.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? WowColors.accent.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Text(
          label,
          style: WowType.body(12, color: selected ? WowColors.text : WowColors.muted, height: 1.2),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Text(label, style: WowType.monoLabel(9, color: WowColors.muted, spacing: 0.6)),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.index, required this.title, required this.subtitle, required this.children});
  final int index;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
      decoration: BoxDecoration(
        color: WowColors.panel.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(index.toString().padLeft(2, '0'),
                style: WowType.monoLabel(9, color: WowColors.accent.withValues(alpha: 0.7), spacing: 1.4)),
            const SizedBox(width: 12),
            Text(title, style: WowType.display(24, FontWeight.w600, spacing: -0.5, height: 1.0)),
            const SizedBox(width: 20),
            Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.07))),
          ],
        ),
        const SizedBox(height: 9),
        Text(subtitle, style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.3), spacing: 1.8)),
        const SizedBox(height: 20),
        ...children,
      ]),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.source, required this.busy, required this.onRescan, required this.onRemove});
  final MediaSource source;
  final bool busy;
  final VoidCallback onRescan;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.035), borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(9), color: WowColors.accent.withValues(alpha: 0.14)),
          child: Icon(source.kind == SourceKind.local ? Icons.folder_rounded : Icons.cloud_rounded, size: 17, color: WowColors.accent),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(source.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: WowType.body(13, height: 1.3))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: WowColors.line),
                ),
                child: Text(_kindLabel(source.kind), style: WowType.monoLabel(7.5, color: WowColors.faint, spacing: 1.0)),
              ),
            ]),
            const SizedBox(height: 3),
            Text(source.location, maxLines: 1, overflow: TextOverflow.ellipsis, style: WowType.monoLabel(9, color: WowColors.faint, spacing: 0.2)),
          ]),
        ),
        IconButton(onPressed: busy ? null : onRescan, icon: const Icon(Icons.refresh_rounded, size: 17), color: WowColors.muted, tooltip: '重新扫描'),
        IconButton(onPressed: onRemove, icon: const Icon(Icons.close_rounded, size: 16), color: WowColors.muted, tooltip: '移除'),
      ]),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({required this.title, required this.detail, required this.value, required this.onChanged});
  final String title;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: WowType.body(12.5, height: 1.3)),
            const SizedBox(height: 2),
            Text(detail, style: WowType.monoLabel(8.5, color: WowColors.faint, spacing: 0.4)),
          ]),
        ),
        _WowSwitch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

class _WowSwitch extends StatelessWidget {
  const _WowSwitch({required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: WowMotion.snappy,
        width: 40,
        height: 23,
        padding: const EdgeInsets.all(2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: value ? LinearGradient(colors: [WowColors.accent, WowColors.accent2]) : null,
          color: value ? null : Colors.white.withValues(alpha: 0.10),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          curve: WowMotion.snappy,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 18, height: 18, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Text(label, style: WowType.monoLabel(9, color: WowColors.faint, spacing: 1.2)),
        const Spacer(),
        Text(value, style: WowType.monoLabel(9.5, color: WowColors.muted, spacing: 1.2)),
      ]),
    );
  }
}


String _kindLabel(SourceKind kind) {
  switch (kind) {
    case SourceKind.local:
      return 'LOCAL';
    case SourceKind.smb:
      return 'SMB';
    case SourceKind.webdav:
      return 'WEBDAV';
    case SourceKind.emby:
      return 'EMBY';
    case SourceKind.jellyfin:
      return 'JELLYFIN';
    case SourceKind.plex:
      return 'PLEX';
    case SourceKind.dlna:
      return 'DLNA';
    case SourceKind.iptv:
      return 'IPTV';
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: WowColors.accent.withValues(alpha: 0.10),
          border: Border.all(color: WowColors.accent.withValues(alpha: 0.24)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: WowColors.accent),
          const SizedBox(width: 8),
          Text(label, style: WowType.monoLabel(11, color: WowColors.text, spacing: 0.6)),
        ]),
      ),
    );
  }
}

class _NetworkSourceResult {
  const _NetworkSourceResult({required this.kind, required this.name, required this.location, required this.username, required this.password});
  final SourceKind kind;
  final String name;
  final String location;
  final String username;
  final String password;
}

class _NetworkSourceDialog extends StatefulWidget {
  const _NetworkSourceDialog();

  @override
  State<_NetworkSourceDialog> createState() => _NetworkSourceDialogState();
}

class _NetworkSourceDialogState extends State<_NetworkSourceDialog> {
  SourceKind _kind = SourceKind.smb;
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _location.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _isSmb => _kind == SourceKind.smb;

  void _submit() {
    final location = _location.text.trim();
    if (location.isEmpty) {
      setState(() => _error = _isSmb ? '请填写 smb://主机/共享名' : '请填写 http(s)://主机/路径');
      return;
    }
    if (_isSmb && !RegExp(r'^(smb://)?[^/]+/.+').hasMatch(location)) {
      setState(() => _error = 'SMB 地址需要包含共享名，例如 smb://192.168.1.10/media');
      return;
    }
    if (!_isSmb && !RegExp(r'^https?://[^/]+').hasMatch(location)) {
      setState(() => _error = 'WebDAV 地址需要以 http:// 或 https:// 开头');
      return;
    }
    final fallbackName = _isSmb ? 'SMB 共享' : 'WebDAV';
    final name = _name.text.trim().isEmpty ? fallbackName : _name.text.trim();
    Navigator.of(context).pop(_NetworkSourceResult(
      kind: _kind,
      name: name,
      location: location,
      username: _username.text.trim(),
      password: _password.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: WowColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: WowColors.line)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('添加网络位置', style: WowType.display(21, FontWeight.w600, spacing: -0.3)),
            const SizedBox(height: 6),
            Text('SMB / NAS 走系统挂载，WebDAV 走 HTTP 直读；密码存入系统钥匙串。',
                style: WowType.body(11, color: WowColors.faint, height: 1.5)),
            const SizedBox(height: 18),
            Row(children: [
              _KindChip(label: 'SMB / NAS', selected: _isSmb, onTap: () => setState(() => _kind = SourceKind.smb)),
              const SizedBox(width: 8),
              _KindChip(label: 'WebDAV', selected: !_isSmb, onTap: () => setState(() => _kind = SourceKind.webdav)),
            ]),
            const SizedBox(height: 16),
            _Field(label: '显示名', controller: _name, hint: _isSmb ? '家里的 NAS' : '我的 WebDAV'),
            const SizedBox(height: 12),
            _Field(label: '地址', controller: _location, hint: _isSmb ? 'smb://192.168.1.10/media' : 'https://dav.example.com/files'),
            const SizedBox(height: 12),
            _Field(label: '用户名', controller: _username, hint: '可选'),
            const SizedBox(height: 12),
            _Field(label: '密码', controller: _password, hint: '存入钥匙串', obscure: true),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: WowType.monoLabel(9, color: const Color(0xFFFF7A8A), spacing: 0.4)),
            ],
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Pressable(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Text('取消', style: WowType.monoLabel(10, color: WowColors.muted, spacing: 0.8)),
                ),
              ),
              const SizedBox(width: 6),
              Pressable(
                onTap: _submit,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.white),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.link_rounded, size: 15, color: WowColors.ink),
                    const SizedBox(width: 7),
                    Text('连接并扫描', style: WowType.monoLabel(10, color: WowColors.ink, spacing: 0.6)),
                  ]),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          color: selected ? WowColors.accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: selected ? WowColors.accent.withValues(alpha: 0.5) : WowColors.line),
        ),
        child: Text(label, style: WowType.monoLabel(9.5, color: selected ? WowColors.accent : WowColors.muted, spacing: 1.0)),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller, required this.hint, this.obscure = false});
  final String label;
  final TextEditingController controller;
  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: WowType.monoLabel(8.5, color: WowColors.faint, spacing: 1.2)),
      const SizedBox(height: 6),
      TextField(
        controller: controller,
        obscureText: obscure,
        style: WowType.body(12.5),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: WowType.body(12, color: WowColors.faint.withValues(alpha: 0.7)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.04),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: WowColors.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: WowColors.accent.withValues(alpha: 0.6))),
        ),
      ),
    ]);
  }
}