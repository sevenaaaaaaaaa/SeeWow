import 'dart:io';

import 'package:flutter/material.dart';

import '../data/iptv_store.dart';
import '../design/pressable.dart';
import '../design/tokens.dart';
import '../domain/iptv.dart';
import '../domain/media_item.dart';

enum _Filter { all, favorites, recent }

class LiveView extends StatefulWidget {
  const LiveView({super.key, required this.store, required this.onPlay});
  final IPTVStore store;
  final void Function(MediaItem item, {bool live}) onPlay;

  @override
  State<LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<LiveView> {
  final _search = TextEditingController();
  String _query = '';
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    switch (Platform.environment['SEEWOW_LIVE_FILTER']) {
      case 'favorites':
        _filter = _Filter.favorites;
      case 'recent':
        _filter = _Filter.recent;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _play(IPTVChannel channel) async {
    await widget.store.markWatched(channel);
    widget.onPlay(
      MediaItem(
        id: channel.id,
        sourceId: channel.playlistId,
        kind: MediaKind.other,
        title: channel.name,
        locator: channel.url,
        posterUrl: channel.logo.isEmpty ? null : channel.logo,
        quality: 'LIVE',
      ),
      live: true,
    );
  }

  Future<void> _addDialog({IPTVPlaylist? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final sourceCtrl = TextEditingController(text: existing?.source ?? '');
    final epgCtrl = TextEditingController(text: existing?.epgUrl ?? '');
    final added = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => _AddPlaylistDialog(
        nameCtrl: nameCtrl,
        sourceCtrl: sourceCtrl,
        epgCtrl: epgCtrl,
        store: widget.store,
        existing: existing,
      ),
    );
    nameCtrl.dispose();
    sourceCtrl.dispose();
    epgCtrl.dispose();
    if (added == true && mounted) setState(() {});
  }

  List<IPTVChannel> get _visible {
    final base = _filter == _Filter.favorites
        ? widget.store.favoriteChannels
        : _filter == _Filter.recent
            ? widget.store.recentChannels
            : widget.store.channels;
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return base;
    return base.where((c) => c.name.toLowerCase().contains(q) || c.group.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final list = _visible;
    final groups = M3UParser.group(list);
    final onAir = store.hasEpg && _filter == _Filter.all && _query.isEmpty ? store.nowOnAir() : const <NowOnAir>[];
    final gutter = WowSpace.gutter(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(width: 4, height: 4, decoration: BoxDecoration(shape: BoxShape.circle, color: WowColors.accent.withValues(alpha: 0.9))),
              const SizedBox(width: 10),
              Text('LIVE TELEVISION', style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.34), spacing: 2.4)),
              const Spacer(),
              _SearchField(controller: _search, onChanged: (v) => setState(() => _query = v)),
              const SizedBox(width: 10),
              _iconButton(Icons.add_rounded, () => _addDialog(), tip: '添加直播源'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('直播', style: WowType.display(46, FontWeight.w400, spacing: -1.2, height: 1.0)),
              const SizedBox(width: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(store.channels.length.toString().padLeft(2, '0') + '  CHANNELS',
                    style: WowType.monoLabel(8.5, color: Colors.white.withValues(alpha: 0.3), spacing: 2.2)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.07)),
          const SizedBox(height: 18),
          Row(
            children: [
              _filterChip('全部', _Filter.all),
              const SizedBox(width: 8),
              _filterChip('收藏', _Filter.favorites),
              const SizedBox(width: 8),
              _filterChip('最近', _Filter.recent),
              const SizedBox(width: 16),
              if (store.playlists.isNotEmpty)
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: store.playlists.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final p = store.playlists[i];
                        return _PlaylistChip(
                          playlist: p,
                          onReload: () => store.reload(p),
                          onEpg: () => _addDialog(existing: p),
                          onRemove: () => store.removePlaylist(p),
                        );
                      },
                    ),
                  ),
                )
              else
                const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: store.channels.isEmpty
                ? _EmptyLive(onAdd: () => _addDialog(), loading: store.loading)
                : list.isEmpty
                    ? _NoResults(filter: _filter)
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 60),
                        children: [
                          if (onAir.isNotEmpty) ...[
                            SectionHeading(index: 1, title: '正在播', subtitle: '0' + onAir.length.toString() + ' ON AIR NOW'),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 92,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: onAir.length,
                                separatorBuilder: (_, _) => const SizedBox(width: 12),
                                itemBuilder: (context, i) => _OnAirCard(entry: onAir[i], onTap: () => _play(onAir[i].channel)),
                              ),
                            ),
                            const SizedBox(height: 26),
                          ],
                          for (var gi = 0; gi < groups.entries.length; gi++) ...[
                            SectionHeading(
                              index: (onAir.isNotEmpty ? 2 : 1) + gi,
                              title: groups.entries.elementAt(gi).key,
                              subtitle: groups.entries.elementAt(gi).value.length.toString().padLeft(2, '0') + ' CHANNELS',
                            ),
                            const SizedBox(height: 16),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 214,
                                mainAxisExtent: 84,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                              ),
                              itemCount: groups.entries.elementAt(gi).value.length,
                              itemBuilder: (context, i) => _ChannelTile(
                                channel: groups.entries.elementAt(gi).value[i],
                                store: store,
                                onTap: () => _play(groups.entries.elementAt(gi).value[i]),
                                onFavorite: () => store.toggleFavorite(groups.entries.elementAt(gi).value[i]),
                              ),
                            ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _Filter value) {
    final active = _filter == value;
    return Pressable(
      onTap: () => setState(() => _filter = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? WowColors.accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: active ? WowColors.accent.withValues(alpha: 0.45) : WowColors.line),
        ),
        child: Text(label,
            style: WowType.body(11.5, height: 1.2, color: active ? WowColors.text : WowColors.muted)),
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap, {String? tip}) {
    return Tooltip(
      message: tip ?? '',
      child: Pressable(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: WowColors.line),
          ),
          child: Icon(icon, size: 18, color: WowColors.text),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WowColors.line),
      ),
      child: Row(children: [
        Icon(Icons.search_rounded, size: 15, color: Colors.white.withValues(alpha: 0.35)),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: WowType.body(12.5, height: 1.2),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: '搜索频道',
              hintStyle: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.28)),
            ),
          ),
        ),
        Text('⌘K', style: WowType.monoLabel(8, color: Colors.white.withValues(alpha: 0.25), spacing: 0.6)),
      ]),
    );
  }
}

class _PlaylistChip extends StatelessWidget {
  const _PlaylistChip({required this.playlist, required this.onReload, required this.onEpg, required this.onRemove});
  final IPTVPlaylist playlist;
  final VoidCallback onReload;
  final VoidCallback onEpg;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final hasEpg = (playlist.epgUrl ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: WowColors.line),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.live_tv_rounded, size: 13, color: WowColors.accent.withValues(alpha: 0.9)),
        const SizedBox(width: 7),
        Text(playlist.name, style: WowType.body(11.5, height: 1.2)),
        const SizedBox(width: 8),
        Text(
          hasEpg ? playlist.channelCount.toString() + ' · EPG' : playlist.channelCount.toString(),
          style: WowType.monoLabel(8.5, color: hasEpg ? WowColors.accent : WowColors.faint, spacing: 0.8),
        ),
        _chipAction(hasEpg ? Icons.event_available_rounded : Icons.event_note_rounded, onEpg,
            tip: hasEpg ? '更新节目单 / 编辑' : '添加节目单'),
        _chipAction(Icons.refresh_rounded, onReload, tip: '重新扫描'),
        _chipAction(Icons.close_rounded, onRemove, tip: '移除', size: 12),
      ]),
    );
  }

  Widget _chipAction(IconData icon, VoidCallback onTap, {String? tip, double size = 13}) {
    return Tooltip(
      message: tip ?? '',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: size, color: Colors.white.withValues(alpha: 0.45)),
        ),
      ),
    );
  }
}

class _OnAirCard extends StatefulWidget {
  const _OnAirCard({required this.entry, required this.onTap});
  final NowOnAir entry;
  final VoidCallback onTap;

  @override
  State<_OnAirCard> createState() => _OnAirCardState();
}

class _OnAirCardState extends State<_OnAirCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.entry.program;
    final progress = p.progressAt(DateTime.now());
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 268,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover ? 0.08 : 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hover ? WowColors.accent.withValues(alpha: 0.35) : WowColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 5, height: 5, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFD5372F))),
              const SizedBox(width: 6),
              Expanded(
                child: Text(widget.entry.channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WowType.monoLabel(8.5, color: WowColors.faint, spacing: 1).copyWith(height: 1.2)),
              ),
              Text(_clock(p.start) + ' – ' + _clock(p.stop),
                  style: WowType.monoLabel(8, color: WowColors.faint, spacing: 0.6)),
            ]),
            const SizedBox(height: 7),
            Text(p.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WowType.display(14.5, FontWeight.w600, spacing: 0)),
            const Spacer(),
            ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(WowColors.accent.withValues(alpha: 0.85)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({required this.channel, required this.store, required this.onTap, required this.onFavorite});
  final IPTVChannel channel;
  final IPTVStore store;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final now = widget.store.nowPlaying(widget.channel);
    final fav = widget.store.isFavorite(widget.channel);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Pressable(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: _hover ? 0.08 : 0.035),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _hover ? WowColors.accent.withValues(alpha: 0.35) : WowColors.line),
          ),
          child: Row(children: [
            _ChannelLogo(channel: widget.channel),
            const SizedBox(width: 11),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WowType.body(12.5, height: 1.2)),
                const SizedBox(height: 3),
                if (now != null) ...[
                  Text(now.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WowType.monoLabel(8.5, color: WowColors.muted, spacing: 0.4).copyWith(height: 1.2)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: LinearProgressIndicator(
                      value: now.progressAt(DateTime.now()),
                      minHeight: 2,
                      backgroundColor: Colors.white.withValues(alpha: 0.07),
                      valueColor: AlwaysStoppedAnimation(WowColors.accent.withValues(alpha: 0.7)),
                    ),
                  ),
                ] else
                  Text(widget.channel.group,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: WowType.monoLabel(8, color: WowColors.faint, spacing: 0.6)),
              ]),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: fav ? 1 : (_hover ? 0.62 : 0.26),
              child: InkWell(
                onTap: widget.onFavorite,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 15, color: fav ? WowColors.accent : Colors.white),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel});
  final IPTVChannel channel;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(colors: [WowColors.accent.withValues(alpha: 0.35), WowColors.accent2.withValues(alpha: 0.2)]),
      ),
      child: Text(
        channel.name.isEmpty ? '?' : channel.name.characters.first,
        style: WowType.display(16, FontWeight.w600, spacing: 0),
      ),
    );
    if (channel.logo.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        channel.logo,
        width: 38,
        height: 38,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.filter});
  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final message = filter == _Filter.favorites
        ? '还没有收藏的频道，把鼠标移到频道上点星号。'
        : filter == _Filter.recent
            ? '看过直播后，这里会记住最近播放的频道。'
            : '没有匹配的频道。';
    return Center(
      child: Text(message, style: WowType.body(12.5, color: WowColors.muted)),
    );
  }
}

class _EmptyLive extends StatelessWidget {
  const _EmptyLive({required this.onAdd, required this.loading});
  final VoidCallback onAdd;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [WowColors.accent.withValues(alpha: 0.35), Colors.transparent]),
          ),
          child: Icon(Icons.sensors_rounded, size: 30, color: WowColors.text),
        ),
        const SizedBox(height: 22),
        Text('接上你的直播源', style: WowType.display(30, FontWeight.w500, spacing: -0.6)),
        const SizedBox(height: 10),
        SizedBox(
          width: 460,
          child: Text('支持 M3U / M3U8 播放列表与 XMLTV 节目单，频道会自动按分组整理，并显示正在播。',
              textAlign: TextAlign.center,
              style: WowType.body(12.5, color: WowColors.muted).copyWith(height: 1.7)),
        ),
        const SizedBox(height: 24),
        Pressable(
          onTap: loading ? null : onAdd,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(color: WowColors.text, borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.add_rounded, size: 17, color: WowColors.ink),
              const SizedBox(width: 8),
              Text(loading ? '正在读取…' : '添加直播源',
                  style: WowType.monoLabel(10.5, color: WowColors.ink, spacing: 0.4).copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _AddPlaylistDialog extends StatefulWidget {
  const _AddPlaylistDialog({
    required this.nameCtrl,
    required this.sourceCtrl,
    required this.epgCtrl,
    required this.store,
    this.existing,
  });
  final TextEditingController nameCtrl;
  final TextEditingController sourceCtrl;
  final TextEditingController epgCtrl;
  final IPTVStore store;
  final IPTVPlaylist? existing;

  @override
  State<_AddPlaylistDialog> createState() => _AddPlaylistDialogState();
}

class _AddPlaylistDialogState extends State<_AddPlaylistDialog> {
  bool _busy = false;
  String? _error;

  bool get _editing => widget.existing != null;

  Future<void> _submit() async {
    final source = widget.sourceCtrl.text.trim();
    if (source.isEmpty) {
      setState(() => _error = '需要一个 M3U 链接或本地文件路径');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    var ok = false;
    if (_editing) {
      await widget.store.setEpgUrl(widget.existing!, widget.epgCtrl.text);
      ok = true;
    } else {
      ok = await widget.store.addPlaylist(
        name: widget.nameCtrl.text,
        source: source,
        epgUrl: widget.epgCtrl.text,
      );
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = widget.store.toast;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 500,
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
        decoration: BoxDecoration(
          color: const Color(0xFF0C0F15),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: WowColors.line),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 60, offset: const Offset(0, 30))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_editing ? '节目单' : '添加直播源', style: WowType.display(24, FontWeight.w600, spacing: -0.4)),
          const SizedBox(height: 6),
          Text(_editing ? 'XMLTV / EPG' : 'M3U PLAYLIST + XMLTV GUIDE',
              style: WowType.monoLabel(8.5, color: WowColors.faint, spacing: 2)),
          const SizedBox(height: 20),
          _field('名称（可选）', widget.nameCtrl, hint: '例如：我的直播源'),
          const SizedBox(height: 12),
          _field('播放列表链接或文件路径', widget.sourceCtrl,
              hint: 'https://…/playlist.m3u 或 /path/list.m3u'),
          const SizedBox(height: 12),
          _field('节目单地址（可选）', widget.epgCtrl, hint: 'https://…/epg.xml'),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: WowType.body(11.5, color: const Color(0xFFFF8A8A), height: 1.4)),
          ],
          const SizedBox(height: 20),
          Row(children: [
            const Spacer(),
            Pressable(
              onTap: _busy ? null : () => Navigator.of(context).pop(false),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                alignment: Alignment.center,
                child: Text('取消', style: WowType.monoLabel(10.5, color: WowColors.muted, spacing: 0.6)),
              ),
            ),
            const SizedBox(width: 6),
            Pressable(
              onTap: _busy ? null : _submit,
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: WowColors.text, borderRadius: BorderRadius.circular(19)),
                child: Text(_busy ? '读取中…' : (_editing ? '保存并更新' : '添加'),
                    style: WowType.monoLabel(10.5, color: WowColors.ink, spacing: 0.6).copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {String? hint}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: WowType.monoLabel(8.5, color: WowColors.faint, spacing: 1.4)),
      const SizedBox(height: 7),
      Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: WowColors.line),
        ),
        child: TextField(
          controller: controller,
          style: WowType.body(12.5, height: 1.2),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.25)),
          ),
        ),
      ),
    ]);
  }
}

String _clock(DateTime t) => t.hour.toString().padLeft(2, '0') + ':' + t.minute.toString().padLeft(2, '0');