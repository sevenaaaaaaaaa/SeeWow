import 'package:flutter/material.dart';

import '../playback/playback_preferences.dart';

Future<void> configurePlayback(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const PlaybackSettingsView(),
);

class PlaybackSettingsView extends StatefulWidget {
  const PlaybackSettingsView({super.key});
  @override
  State<PlaybackSettingsView> createState() => _PlaybackSettingsViewState();
}

class _PlaybackSettingsViewState extends State<PlaybackSettingsView> {
  final _prefs = PlaybackPreferences.I;
  late EntranceStyle _entrance = _prefs.entrance;
  late bool _fullscreen = _prefs.fullscreen,
      _background = _prefs.background,
      _meter = _prefs.meter;
  late bool _sensitiveScan = _prefs.sensitiveScan;
  late final _sensitiveEndpoint = TextEditingController(
    text: _prefs.sensitiveEndpoint,
  );
  @override
  void dispose() {
    _sensitiveEndpoint.dispose();
    super.dispose();
  }

  bool _busy = false;
  String? _error;
  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _prefs.save(
        entrance: _entrance,
        fullscreen: _fullscreen,
        background: _background,
        meter: _meter,
        sensitiveScan: _sensitiveScan,
        sensitiveEndpoint: _sensitiveEndpoint.text,
      );
      if (mounted) Navigator.pop(context);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '播放偏好保存失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('放映与播放'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<EntranceStyle>(
              initialValue: _entrance,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '放映入场'),
              items: const [
                DropdownMenuItem(
                  value: EntranceStyle.disc,
                  child: Text('光盘旋入'),
                ),
                DropdownMenuItem(
                  value: EntranceStyle.spotlight,
                  child: Text('SeeWow 聚光片头'),
                ),
                DropdownMenuItem(
                  value: EntranceStyle.none,
                  child: Text('直接放映'),
                ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _entrance = v!),
            ),
            const SizedBox(height: 10),
            const Text('片头约两秒，可随时跳过。系统减少动态效果时直接进入影片；直播和音频不播放片头。'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _fullscreen,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _fullscreen = v ?? false),
              title: const Text('播放影片时进入全屏'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _background,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _background = v ?? false),
              title: const Text('允许切到后台继续原声播放'),
              subtitle: const Text('移动端需系统后台播放支持；AI 请求在后台停止。关闭播放器会停止播放。'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _meter,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _meter = v ?? false),
              title: const Text('显示原片音频电平'),
              subtitle: const Text('通过解码器读取 RMS 响度；不支持的音频输出会显示不可用，不显示随机波形。'),
            ),
            const Divider(),
            const Text(
              '静音与触控保护',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              '新文件默认静音，双击画面恢复声音。外放默认最高 30%，已确认耳机默认最高 50%；当天调低过则取更低值。手动调高只影响当前播放，次日清除记录。',
            ),
            const SizedBox(height: 8),
            const Text(
              '滑动画面或左右长按可预览进度，松手跳转。双指或更多手指长按锁定触控并继续后台原声播放；同样手势或长按锁按钮解锁。',
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _sensitiveScan,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _sensitiveScan = v ?? false),
              title: const Text('启用用户自备的本机敏感画面检测'),
              subtitle: const Text(
                '开启即允许每 3 秒将一张缩小的当前画面交给下方本机服务。不会发送到云端；后台和系统小窗停止抽帧。Telegram 来源不启用。',
              ),
            ),
            if (_sensitiveScan)
              TextField(
                controller: _sensitiveEndpoint,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: '本机检测地址',
                  hintText: 'http://127.0.0.1:端口/classify',
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              '明确的成人内容标记、手动敏感标记或检测阳性会锁住本片外放静音。未配置检测时仅检查标记；抽帧检测可能漏检。无法确认的蓝牙或共享输出按外放保护。此处百分比为播放器音量，不修改系统音量。',
            ),
            if (_error != null) Text(_error!),
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
        child: const Text('保存播放偏好'),
      ),
    ],
  );
}
