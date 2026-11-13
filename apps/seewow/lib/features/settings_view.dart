import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/cinema_widgets.dart';
import '../design/skin.dart';
import '../design/tokens.dart';
import 'metadata_dialog.dart';
import 'remote_view.dart';
import 'custom_scraper_view.dart';
import 'cover_generation_view.dart';
import 'playback_settings_view.dart';
import 'frame_bookmarks_view.dart';
import 'voice_translation_view.dart';
import 'subtitle_dialog.dart';
import '../metadata/subtitles.dart';
import 'skin_studio.dart';
import 'watch_ai_view.dart';
import '../agent/agent_controller.dart';
import '../downloads/download_manager.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.store,
    this.onConfigureAgent,
    this.onSources,
    this.agent,
    this.downloads,
    this.onOpenDownloads,
  });
  final LibraryStore store;
  final AgentController? agent;
  final VoidCallback? onConfigureAgent, onSources;
  final DownloadManager? downloads;
  final VoidCallback? onOpenDownloads;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: downloads == null
        ? WowSkin.I
        : Listenable.merge([WowSkin.I, downloads!]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) => ListView(
        padding: EdgeInsets.all(box.maxWidth < 700 ? 20 : 32),
        children: [
          const PageIntro(
            eyebrow: 'MAKE YOURSELF AT HOME',
            title: '影院偏好',
            description: '让工具适应你，保持舒服、清楚、可控。',
          ),
          const SizedBox(height: 24),
          CinemaPanel(child: SkinStudio(agent: agent)),
          const SizedBox(height: 16),
          CinemaPanel(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.auto_awesome_outlined,
                    color: WowColors.accent,
                  ),
                  title: const Text('AI 模型', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '接入兼容服务，或使用本地规则模式',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onConfigureAgent,
                ),
                Divider(color: WowColors.line),
                const WatchAiSettingsTile(),
                if (downloads != null)
                  ListTile(
                    leading: const Icon(Icons.download_for_offline_outlined),
                    title: const Text('离线缓存'),
                    subtitle: Text(
                      downloads!.completedCount > 0
                          ? '${downloads!.completedCount} 部已离线 · ${downloads!.activeCount} 个进行中'
                          : '缓存到本地，片源离线也能播放',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: onOpenDownloads,
                  ),
                ListTile(
                  leading: const Icon(Icons.settings_remote_outlined),
                  title: const Text('手机遥控电脑'),
                  subtitle: const Text('同一 Wi-Fi 下，用手机控制电脑上的播放'),
                  onTap: () => showRemoteControl(context),
                ),
                ListTile(
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: const Text('语音译配 API · 实验性'),
                  subtitle: const Text('目标语言配音、服务声明保留音色；分段缓冲'),
                  onTap: () => configureVoiceTranslation(context),
                ),
                ListTile(
                  leading: const Icon(Icons.theaters_outlined),
                  title: const Text('放映与播放'),
                  subtitle: const Text('入场片头、全屏、后台播放和音频电平'),
                  onTap: () => configurePlayback(context),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('精彩帧收藏'),
                  subtitle: const Text('本机保存的影片画面与时间点'),
                  onTap: () => showFrameBookmarks(context),
                ),
                Divider(color: WowColors.line),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.manage_search, color: WowColors.accent),
                  title: const Text('影片信息补全', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '多语言与地区、封面、演职员和评分；预览后确认',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => configureMetadata(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.api_outlined),
                  title: const Text('自定义刮削 API'),
                  subtitle: const Text('按视频类型配置资料接口与 JSON 字段映射'),
                  onTap: () => configureCustomScrapers(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('AI 封面服务'),
                  subtitle: const Text('用户自配图像模型；缺少封面时生成原创配图'),
                  onTap: () => configureCoverGeneration(context),
                ),
                const Divider(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.subtitles_outlined),
                  title: const Text('在线字幕服务'),
                  subtitle: const Text('OpenSubtitles · 用户自配 API Key 与可选账号'),
                  onTap: () => configureSubtitles(context),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('清理下载字幕缓存'),
                  subtitle: const Text('仅删除 SeeWow 下载缓存，保留媒体与本地旁车文件'),
                  onTap: () async {
                    try {
                      await SubtitleCache().clear();
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('字幕下载缓存已清理')),
                        );
                    } catch (_) {
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('缓存清理失败，请停止播放后重试')),
                        );
                    }
                  },
                ),
                Divider(color: WowColors.line),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.hub_outlined, color: WowColors.accent),
                  title: const Text('片源与订阅', style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '${store.sources.length} 个来源 · NAS、网盘、媒体与音乐服务',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onSources,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CinemaPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(
                  '关于 SeeWow',
                  subtitle: '1.6.0 · Cinema, made personal.',
                ),
                const SizedBox(height: 16),
                Text(
                  '播放：media_kit / libmpv，支持断点续播与播放速度。\n片库、偏好、片单与任务记录保存在本机。\n网盘通过 WebDAV 网关接入；原生网盘登录和全网资源搜索尚未提供。影片信息可通过 TMDB 主动匹配；本地、SMB 与 WebDAV 扫描自动读取 NFO 中文资料。',
                  style: WowType.body(12, color: WowColors.muted),
                ),
                const SizedBox(height: 16),
                const TmdbCredit(),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
