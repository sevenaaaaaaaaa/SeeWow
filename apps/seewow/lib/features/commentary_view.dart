import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../playback/commentary_controller.dart';
import '../watch_ai/watch_ai_settings.dart';

/// Commentary (解说) entry point for the player.
///
/// The whole loop stays on this machine: the script comes from the model the
/// user already configured for AI companion, and the voice is the operating
/// system's own TTS. No audio is uploaded anywhere.
Future<void> showCommentaryDialog(
  BuildContext context, {
  required CommentaryController controller,
  required WatchAiConfig config,
  required double durationSeconds,
}) => showDialog<void>(
  context: context,
  builder: (context) => _CommentaryDialog(
    controller: controller,
    config: config,
    durationSeconds: durationSeconds,
  ),
);

class _CommentaryDialog extends StatefulWidget {
  const _CommentaryDialog({
    required this.controller,
    required this.config,
    required this.durationSeconds,
  });

  final CommentaryController controller;
  final WatchAiConfig config;
  final double durationSeconds;

  @override
  State<_CommentaryDialog> createState() => _CommentaryDialogState();
}

class _CommentaryDialogState extends State<_CommentaryDialog> {
  String _style = '影评人';
  int _count = 8;
  CommentaryMode _mode = CommentaryMode.full;
  String? _error;
  String? _notice;

  static const _styles = ['影评人', '科普', '剧情回顾', '轻松吐槽'];

  CommentaryController get _c => widget.controller;

  Future<void> _generate() async {
    setState(() {
      _error = null;
      _notice = '正在生成解说脚本…';
    });
    try {
      final count = await _c.generate(
        config: widget.config,
        durationSeconds: widget.durationSeconds,
        style: _style,
        segmentCount: _count,
        mode: _mode,
      );
      if (!mounted) return;
      setState(() => _notice = '已生成 $count 段解说，点「开始解说」跟着影片播放');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = null;
        _error = e.toString();
      });
    }
  }

  Future<void> _export() async {
    setState(() {
      _error = null;
      _notice = '正在合成解说音轨…';
    });
    try {
      final result = await _c.exportTrack();
      final bytes = await result.track.readAsBytes();
      final path = await FilePicker.saveFile(
        dialogTitle: '保存解说音轨',
        fileName: '解说音轨.wav',
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() {
        _notice = path == null
            ? '已合成 ${result.duration.toStringAsFixed(0)} 秒音轨，未保存'
            : '已保存 ${result.segments} 段解说，时长 ${result.duration.toStringAsFixed(0)} 秒';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _notice = null;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _toggle() async {
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      if (_c.speaking) {
        await _c.stop();
        if (mounted) setState(() => _notice = '已停止解说，原声音量已恢复');
      } else {
        await _c.start();
        if (mounted) setState(() => _notice = '解说已开启，音量大小时会自动压低影片原声');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => AlertDialog(
        title: const Text('自动解说'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '用你已经配置好的模型写解说词，用系统自带的语音朗读。'
                  '可以只做片头 30 秒，也可以铺满全片；导出的是一条带静默间隔的 WAV 音轨。'
                  '解说播放时会压低影片原声而不是静音；不会上传影片画面或声音。',
                  style: WowType.body(12, color: WowColors.muted),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 170,
                      child: DropdownButtonFormField<CommentaryMode>(
                        initialValue: _mode,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '解说范围'),
                        items: const [
                          DropdownMenuItem(
                            value: CommentaryMode.intro,
                            child: Text('片头 30 秒'),
                          ),
                          DropdownMenuItem(
                            value: CommentaryMode.full,
                            child: Text('全片'),
                          ),
                        ],
                        onChanged: _c.generating
                            ? null
                            : (value) {
                                if (value != null) setState(() => _mode = value);
                              },
                      ),
                    ),
                    SizedBox(
                      width: 170,
                      child: DropdownButtonFormField<String>(
                        initialValue: _style,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '解说风格'),
                        items: [
                          for (final style in _styles)
                            DropdownMenuItem(value: style, child: Text(style)),
                        ],
                        onChanged: _c.generating
                            ? null
                            : (value) {
                                if (value != null) setState(() => _style = value);
                              },
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: DropdownButtonFormField<int>(
                        initialValue: _count,
                        decoration: const InputDecoration(labelText: '段数'),
                        items: [
                          for (final n in [4, 6, 8, 10, 12])
                            DropdownMenuItem(value: n, child: Text('$n 段')),
                        ],
                        onChanged: _c.generating
                            ? null
                            : (value) {
                                if (value != null) setState(() => _count = value);
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_c.segments.isNotEmpty) ...[
                  Text(
                    '解说脚本（${_c.segments.length} 段）',
                    style: WowType.monoLabel(10, color: WowColors.muted),
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _c.segments.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final segment = _c.segments[index];
                        final minutes = segment.at ~/ 60;
                        final seconds = (segment.at % 60).round();
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 58,
                              child: Text(
                                '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                                style: WowType.monoLabel(
                                  10,
                                  color: WowColors.accent,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                segment.text,
                                style: const TextStyle(fontSize: 12, height: 1.5),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _notice!,
                      style: TextStyle(fontSize: 12, color: WowColors.success),
                    ),
                  ),
                if (_error != null || _c.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error ?? _c.error!,
                      style: TextStyle(fontSize: 12, color: WowColors.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          if (_c.segments.isNotEmpty)
            TextButton.icon(
              onPressed: _c.generating ? null : _export,
              icon: const Icon(Icons.download, size: 16),
              label: const Text('导出音轨'),
            ),
          if (_c.segments.isNotEmpty)
            TextButton(
              onPressed: _c.generating ? null : _toggle,
              child: Text(_c.speaking ? '停止解说' : '开始解说'),
            ),
          FilledButton.icon(
            onPressed: _c.generating ? null : _generate,
            icon: _c.generating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 16),
            label: Text(_c.generating ? '生成中…' : '生成解说脚本'),
          ),
        ],
      ),
    );
  }
}
