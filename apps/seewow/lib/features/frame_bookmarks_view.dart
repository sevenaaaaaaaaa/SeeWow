import 'package:flutter/material.dart';

import '../design/artwork.dart';
import '../playback/frame_bookmarks.dart';
import '../playback/playback_preferences.dart';

Future<void> showFrameBookmarks(
  BuildContext context, {
  String? itemId,
  FrameBookmarks? store,
  ValueChanged<FrameBookmark>? onSelect,
}) => showDialog<void>(
  context: context,
  builder: (_) => FrameBookmarksView(
    store: store ?? FrameBookmarks.I,
    itemId: itemId,
    onSelect: onSelect,
  ),
);

class FrameBookmarksView extends StatefulWidget {
  const FrameBookmarksView({
    super.key,
    required this.store,
    this.itemId,
    this.onSelect,
  });
  final FrameBookmarks store;
  final String? itemId;
  final ValueChanged<FrameBookmark>? onSelect;
  @override
  State<FrameBookmarksView> createState() => _FrameBookmarksViewState();
}

class _FrameBookmarksViewState extends State<FrameBookmarksView> {
  List<FrameBookmark>? _frames;
  final _paths = <String, String>{};
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final frames = await widget.store.list(itemId: widget.itemId);
      for (final frame in frames) {
        _paths[frame.id] = await widget.store.path(frame);
      }
      if (mounted)
        setState(() {
          _frames = frames;
          _error = null;
        });
    } catch (_) {
      if (mounted) setState(() => _error = '精彩帧读取失败，请检查本机文件');
    }
  }

  Future<void> _remove(FrameBookmark frame) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('移除这张精彩帧？'),
        content: const Text('仅删除 SeeWow 保存的截图，不改动影片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('移除收藏'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.store.remove(frame);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = '移除失败，请重试');
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('精彩帧收藏'),
    content: SizedBox(
      width: 760,
      height: MediaQuery.sizeOf(context).height * .65,
      child: _error != null
          ? Text(_error!)
          : _frames == null
          ? const Center(child: CircularProgressIndicator())
          : _frames!.isEmpty
          ? const Center(child: Text('还没有收藏画面。在播放器的「播放工具」中收藏当前精彩帧。'))
          : ListView(
              children: [
                for (final frame in _frames!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () => showDialog<void>(
                            context: context,
                            builder: (c) => Dialog(
                              child: InteractiveViewer(
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: WowArt(
                                    url: _paths[frame.id],
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          child: SizedBox(
                            height: 210,
                            width: double.infinity,
                            child: WowArt(
                              url: _paths[frame.id],
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text('${frame.title} · ${playbackTime(frame.seconds)}'),
                        if (frame.note.isNotEmpty) Text(frame.note),
                        Wrap(
                          spacing: 10,
                          children: [
                            if (widget.onSelect != null)
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  widget.onSelect!(frame);
                                },
                                child: const Text('回到此刻'),
                              ),
                            TextButton(
                              onPressed: () => _remove(frame),
                              child: const Text('移除收藏'),
                            ),
                          ],
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
        child: const Text('关闭'),
      ),
    ],
  );
}
