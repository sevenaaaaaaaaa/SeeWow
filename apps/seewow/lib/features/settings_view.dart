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
import '../app/build_info.dart';

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

  String get _agentHost =>
      Uri.tryParse(agent?.endpoint ?? '')?.host ?? '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([WowSkin.I, ?downloads, ?agent]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, box) => ListView(
        padding: EdgeInsets.all(box.maxWidth < 700 ? 20 : 32),
        children: [
          const PageIntro(
            eyebrow: 'SETTINGS',
            title: '设置',
            description: '按类别管理外观、AI、播放、字幕、存储与片源；密钥只保存在本机。',
          ),
          const SizedBox(height: 24),
          _SettingsGroup(
            icon: Icons.auto_awesome_mosaic_outlined,
            title: '外观与氛围',
            subtitle: '主题、材质与动效；也能让 Agent 从 design.md 生成',
            children: [SkinStudio(agent: agent)],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            icon: Icons.auto_awesome_outlined,
            title: 'AI 与智能',
            subtitle: '全部使用你自己配置的服务，密钥只存本机凭据存储',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.auto_awesome_outlined, color: WowColors.accent),
                title: const Text('AI 模型', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  agent?.hasModel == true
                      ? '当前：${agent!.model}'
                            '${_agentHost.isEmpty ? '' : ' · $_agentHost'}'
                      : '未接入 · 使用本地规则模式',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onConfigureAgent,
              ),
              Divider(color: WowColors.line),
              const WatchAiSettingsTile(),
              Divider(color: WowColors.line),
              ListTile(
                leading: const Icon(Icons.record_voice_over_outlined),
                title: const Text('语音译配 API · 实验性'),
                subtitle: const Text('目标语言配音、保留音色；内置分段协议或通用 JSON 映射'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => configureVoiceTranslation(context),
              ),
              Divider(color: WowColors.line),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('AI 封面服务'),
                subtitle: const Text('用户自配图像模型；缺少封面时生成原创配图'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => configureCoverGeneration(context),
              ),
              Divider(color: WowColors.line),
              ListTile(
                leading: const Icon(Icons.manage_search),
                title: const Text('影片信息补全'),
                subtitle: const Text('多语言与地区、封面、演职员和评分；预览后确认'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => configureMetadata(context),
              ),
              Divider(color: WowColors.line),
              ListTile(
                leading: const Icon(Icons.api_outlined),
                title: const Text('自定义刮削 API'),
                subtitle: const Text('按视频类型配置资料接口与 JSON 字段映射'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => configureCustomScrapers(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            icon: Icons.play_circle_outline,
            title: '播放',
            subtitle: '入场片头、全屏、后台播放；也能在局域网内遥控电脑',
            children: [
              ListTile(
                leading: const Icon(Icons.theaters_outlined),
                title: const Text('放映与播放'),
                subtitle: const Text('入场片头、全屏、后台播放和音频电平'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => configurePlayback(context),
              ),
              Divider(color: WowColors.line),
              ListTile(
                leading: const Icon(Icons.settings_remote_outlined),
                title: const Text('手机遥控电脑'),
                subtitle: const Text('同一 Wi-Fi 下，用手机控制电脑上的播放'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showRemoteControl(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _SettingsGroup(
            icon: Icons.subtitles_outlined,
            title: '字幕',
            subtitle: '在线字幕服务与本机缓存',
            children: [
              ListTile(
                leading: const Icon(Icons.subtitles_outlined),
                title: const Text('在线字幕服务'),
                subtitle: const Text('OpenSubtitles · 用户自配 API Key 与可选账号'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => configureSubtitles(context),
              ),
              Divider(color: WowColors.line),
              ListTile(
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
            ],
          ),
          if (downloads != null) ...[
            const SizedBox(height: 18),
            _SettingsGroup(
              icon: Icons.download_for_offline_outlined,
              title: '存储',
              subtitle: '缓存到本机后，片源离线也能播放',
              children: [
                ListTile(
                  leading: const Icon(Icons.download_for_offline_outlined),
                  title: const Text('离线缓存'),
                  subtitle: Text(
                    downloads!.completedCount > 0
                        ? '${downloads!.completedCount} 部已离线 · ${downloads!.activeCount} 个进行中'
                        : '还没有缓存；媒体库「已缓存」筛选可直接查看',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onOpenDownloads,
                ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          _SettingsGroup(
            icon: Icons.video_library_outlined,
            title: '内容与来源',
            subtitle: '片源连接、订阅与收藏的画面',
            children: [
              ListTile(
                leading: Icon(Icons.hub_outlined, color: WowColors.accent),
                title: const Text('片源与订阅', style: TextStyle(fontSize: 14)),
                subtitle: Text(
                  '${store.sources.length} 个来源 · NAS、网盘、媒体与音乐服务',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: onSources,
              ),
              Divider(color: WowColors.line),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('精彩帧收藏'),
                subtitle: const Text('本机保存的影片画面与时间点'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showFrameBookmarks(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          CinemaPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionTitle(
                  '关于 SeeWow',
                  subtitle: '${BuildInfo.label} · Cinema, made personal.',
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

/// A titled settings group: one icon + label above a single panel, so the
/// page reads as groups instead of one long undifferentiated list.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.icon,
    required this.title,
    required this.children,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 15, color: WowColors.muted),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WowType.body(11, color: WowColors.muted),
                ),
              ),
            ],
          ],
        ),
      ),
      CinemaPanel(child: Column(children: children)),
    ],
  );
}
