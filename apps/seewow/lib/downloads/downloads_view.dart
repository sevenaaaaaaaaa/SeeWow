import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../design/cinema_widgets.dart';
import '../design/tokens.dart';
import '../domain/media_item.dart';
import 'download_manager.dart';
import 'download_quality.dart';
import 'download_task.dart';

Future<void> showDownloads(
  BuildContext context, {
  required DownloadManager manager,
  required Future<void> Function(DownloadTask task) onPlay,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => DownloadsPage(manager: manager, onPlay: onPlay),
  ),
);

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key, required this.manager, required this.onPlay});
  final DownloadManager manager;
  final Future<void> Function(DownloadTask task) onPlay;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: manager,
    builder: (context, _) => Scaffold(
      backgroundColor: WowColors.ink,
      appBar: AppBar(backgroundColor: WowColors.ink, title: const Text('离线缓存')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        children: [
          _storagePanel(context),
          const SizedBox(height: 18),
          if (manager.tasks.isEmpty)
            CinemaPanel(
              child: EmptyCinema(
                icon: Icons.download_for_offline_outlined,
                title: '还没有离线影片',
                description: '在影片详情页点「缓存到本地」，选择画质与存放位置；完成后即使片源离线也能播放。',
              ),
            )
          else
            for (final task in manager.tasks.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _taskCard(context, task),
              ),
        ],
      ),
    ),
  );

  Widget _storagePanel(BuildContext context) => CinemaPanel(
    child: FutureBuilder<String>(
      future: manager.storageDir().then((dir) => dir.path),
      builder: (context, snapshot) {
        final path = snapshot.data ?? '存放位置加载中…';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('存放位置', style: WowType.monoLabel(10, color: WowColors.muted)),
            const SizedBox(height: 6),
            SelectableText(
              path,
              style: WowType.body(12, color: WowColors.text),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                Text(
                  '${manager.completedCount} 部已离线 · ${_size(manager.offlineBytes)}',
                  style: TextStyle(fontSize: 11, color: WowColors.muted),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '限速',
                      style: TextStyle(fontSize: 11, color: WowColors.muted),
                    ),
                    const SizedBox(width: 4),
                    DropdownButton<int>(
                      value: manager.speedLimitKbps,
                      underline: const SizedBox.shrink(),
                      style: TextStyle(fontSize: 12, color: WowColors.text),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('不限速')),
                        DropdownMenuItem(value: 1024, child: Text('1 MB/s')),
                        DropdownMenuItem(value: 2048, child: Text('2 MB/s')),
                        DropdownMenuItem(value: 5120, child: Text('5 MB/s')),
                        DropdownMenuItem(value: 10240, child: Text('10 MB/s')),
                        DropdownMenuItem(value: 20480, child: Text('20 MB/s')),
                      ],
                      onChanged: (value) => manager.setSpeedLimit(value ?? 0),
                    ),
                  ],
                ),
                if (!Platform.isIOS)
                  OutlinedButton.icon(
                    onPressed: () => _chooseFolder(context),
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('选择存放位置'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _openFolder(path),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('打开文件夹'),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  Widget _taskCard(BuildContext context, DownloadTask task) {
    final failed = task.isFailed;
    final progressText = [
      '${(task.progress * 100).round()}% · ${_size(task.downloadedBytes)} / ${task.sizeLabel}',
      if (task.speedLabel.isNotEmpty) task.speedLabel,
      if (task.etaLabel.isNotEmpty) task.etaLabel,
    ].join(' · ');
    return CinemaPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                task.isDone
                    ? Icons.offline_pin
                    : failed
                    ? Icons.error_outline
                    : Icons.downloading,
                color: task.isDone
                    ? WowColors.accent
                    : failed
                    ? WowColors.error
                    : WowColors.muted,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WowType.body(14, color: WowColors.text),
                ),
              ),
              Text(
                task.statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  color: task.isDone
                      ? WowColors.accent
                      : failed
                      ? WowColors.error
                      : WowColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${task.sourceName} · ${task.quality} · ${task.sizeLabel}',
            style: TextStyle(fontSize: 11, color: WowColors.muted),
          ),
          if (task.isActive || task.isPaused) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: task.progress,
              minHeight: 3,
              color: WowColors.accent,
            ),
            const SizedBox(height: 6),
            Text(
              progressText,
              style: TextStyle(fontSize: 10, color: WowColors.muted),
            ),
          ],
          if (task.error != null && failed) ...[
            const SizedBox(height: 8),
            Text(
              task.error!,
              style: TextStyle(fontSize: 11, color: WowColors.error),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (task.isDone)
                FilledButton.icon(
                  onPressed: () => onPlay(task),
                  icon: const Icon(Icons.play_arrow, size: 17),
                  label: const Text('离线播放'),
                ),
              if (task.isActive)
                TextButton.icon(
                  onPressed: () => manager.pause(task.id),
                  icon: const Icon(Icons.pause, size: 16),
                  label: const Text('暂停'),
                ),
              if (task.isPaused || failed)
                TextButton.icon(
                  onPressed: () => manager.resume(task.id),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: Text(failed ? '重试' : '继续'),
                ),
              TextButton.icon(
                onPressed: () => manager.remove(task.id),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: Text(task.isActive ? '取消并删除' : '删除文件'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _chooseFolder(BuildContext context) async {
    try {
      final path = await FilePicker.getDirectoryPath(dialogTitle: '选择离线缓存文件夹');
      if (path == null || !context.mounted) return;
      await manager.setStorageDirectory(path);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法选择文件夹：$error')));
    }
  }

  Future<void> _openFolder(String path) async {
    if (path.endsWith('…')) return;
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
      } else if (Platform.isWindows) {
        await Process.run('explorer', [path]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
      }
    } catch (_) {}
  }

  static String _size(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }
}

Future<bool?> showDownloadSheet(
  BuildContext context, {
  required DownloadManager manager,
  required MediaItem item,
  required String sourceName,
  MediaSource? source,
}) => showDialog<bool>(
  context: context,
  builder: (_) => _DownloadSheet(
    manager: manager,
    item: item,
    sourceName: sourceName,
    source: source,
  ),
);

class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({
    required this.manager,
    required this.item,
    required this.sourceName,
    this.source,
  });
  final DownloadManager manager;
  final MediaItem item;
  final String sourceName;
  final MediaSource? source;

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  bool _busy = false;
  String _qualityId = 'original';

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('缓存到本地'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.item.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: WowType.body(14, color: WowColors.text),
          ),
          const SizedBox(height: 4),
          Text(
            '来源：${widget.sourceName}',
            style: TextStyle(fontSize: 11, color: WowColors.muted),
          ),
          const SizedBox(height: 16),
          Text('画质', style: WowType.monoLabel(10, color: WowColors.muted)),
          const SizedBox(height: 4),
          for (final quality in downloadQualitiesFor(widget.source))
            RadioListTile<String>(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: quality.id,
              groupValue: _qualityId,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _qualityId = value ?? 'original'),
              title: Text(quality.label, style: const TextStyle(fontSize: 13)),
            ),
          if (downloadQualitiesFor(widget.source).length == 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '该片源只提供直连文件；转码下载仅支持 Plex / Emby。',
                style: TextStyle(fontSize: 10, color: WowColors.muted),
              ),
            ),
          const SizedBox(height: 8),
          Text('存放位置', style: WowType.monoLabel(10, color: WowColors.muted)),
          const SizedBox(height: 4),
          FutureBuilder<String>(
            future: widget.manager.storageDir().then((dir) => dir.path),
            builder: (context, snapshot) => Text(
              snapshot.data ?? '默认位置',
              style: TextStyle(fontSize: 11, color: WowColors.muted),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '缓存完成后优先播放本地文件；删除缓存不会影响片源。',
            style: TextStyle(fontSize: 10, color: WowColors.muted),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton.icon(
        onPressed: _busy ? null : _start,
        icon: _busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download, size: 17),
        label: const Text('开始缓存'),
      ),
    ],
  );

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await widget.manager.enqueue(
        widget.item,
        source: widget.source,
        sourceName: widget.sourceName,
        qualityId: _qualityId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('无法开始缓存：$error')));
    }
  }
}
