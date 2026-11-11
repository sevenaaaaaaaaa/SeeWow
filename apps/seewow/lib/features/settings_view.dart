import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../design/cinema_widgets.dart';
import '../design/skin.dart';
import '../design/tokens.dart';
import 'metadata_dialog.dart';
import 'skin_studio.dart';
import 'watch_ai_view.dart';
import '../agent/agent_controller.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.store,
    this.onConfigureAgent,
    this.onSources,
    this.agent,
  });
  final LibraryStore store;
  final AgentController? agent;
  final VoidCallback? onConfigureAgent, onSources;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: WowSkin.I,
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
                Divider(color: WowColors.line),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.manage_search, color: WowColors.accent),
                  title: const Text('影片信息补全', style: TextStyle(fontSize: 14)),
                  subtitle: const Text(
                    '配置 TMDB Token，搜索、预览并确认匹配',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => configureMetadata(context),
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
