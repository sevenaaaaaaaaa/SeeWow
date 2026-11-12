import 'media_item.dart';

class SourceProvider {
  const SourceProvider(
    this.id,
    this.name,
    this.category,
    this.modes,
    this.description, {
    this.nativePending = false,
  });
  final String id, name, category, description;
  final List<SourceKind> modes;
  final bool nativePending;
}

const sourceProviders = [
  SourceProvider(
    'telegramLocal',
    'Telegram 本地媒体',
    '本地媒体',
    [SourceKind.local],
    '选择 Telegram 已下载到设备的媒体目录。无需登录；不读取频道或聊天。不向 AI 发送此来源内容。原生账号与频道接入待验证。',
    nativePending: true,
  ),
  SourceProvider(
    'fnos',
    '飞牛 NAS',
    'NAS',
    [SourceKind.smb, SourceKind.webdav, SourceKind.openlist],
    '共享目录接入；可读取已有 NFO。飞牛影视专有接口待接入。',
    nativePending: true,
  ),
  SourceProvider('synology', '群晖 NAS', 'NAS', [
    SourceKind.synology,
    SourceKind.smb,
    SourceKind.webdav,
  ], 'File Station 账号接入，或使用共享目录与 WebDAV。'),
  SourceProvider('plex', 'Plex', '媒体服务器', [
    SourceKind.plex,
  ], 'Plex 账号验证码登录，或手动填写服务器 Token；自动读取电影与剧集目录、海报并原文件播放。'),
  SourceProvider('webdav', 'WebDAV', '通用', [
    SourceKind.webdav,
  ], '标准 WebDAV，支持账号、递归建库和认证播放。'),
  SourceProvider('jellyfin', 'Jellyfin', '媒体服务器', [
    SourceKind.jellyfin,
  ], 'API Key 与可选用户 ID，保留服务器已有元数据。'),
  SourceProvider(
    'quark',
    '夸克网盘',
    '网盘',
    [SourceKind.openlist, SourceKind.webdav],
    '选择 OpenList / Alist 中的夸克挂载目录。',
    nativePending: true,
  ),
  SourceProvider(
    'baidu',
    '百度网盘',
    '网盘',
    [SourceKind.openlist, SourceKind.webdav],
    '选择网关中已授权的百度目录。',
    nativePending: true,
  ),
  SourceProvider(
    'uc',
    'UC 网盘',
    '网盘',
    [SourceKind.openlist, SourceKind.webdav],
    '通过已配置 UC 驱动的网关接入。',
    nativePending: true,
  ),
  SourceProvider(
    'onedrive',
    'OneDrive',
    '网盘',
    [SourceKind.openlist, SourceKind.webdav],
    '使用网关的 OneDrive 挂载，授权由网关维护。',
    nativePending: true,
  ),
  SourceProvider(
    'googleDrive',
    'Google Drive',
    '网盘',
    [SourceKind.openlist, SourceKind.webdav],
    '使用网关的 Google Drive 挂载，授权由网关维护。',
    nativePending: true,
  ),
  SourceProvider(
    'mega',
    'MEGA',
    '网盘',
    [SourceKind.openlist, SourceKind.webdav],
    '需要网关安装并启用 MEGA 驱动。',
    nativePending: true,
  ),
  SourceProvider(
    'pan123',
    '123 云盘',
    '网盘',
    [SourceKind.openlist, SourceKind.webdav],
    '通过已授权的 123 挂载目录读取影片。',
    nativePending: true,
  ),
  SourceProvider(
    'pan115',
    '115 网盘',
    '网盘',
    [SourceKind.openlist, SourceKind.webdav],
    '通过已授权的 115 挂载，播放时解析新地址。',
    nativePending: true,
  ),
  SourceProvider('navidrome', 'Navidrome', '音乐服务器', [
    SourceKind.navidrome,
  ], 'OpenSubsonic 账号，音乐扫描与播放。'),
  SourceProvider('openlist', 'OpenList / Alist', '通用', [
    SourceKind.openlist,
    SourceKind.webdav,
  ], '网关 API 目录扫描与播放前动态解析，或 WebDAV。'),
  SourceProvider('emby', 'Emby', '媒体服务器', [SourceKind.emby], 'API Key 接入媒体库。'),
];
String sourceModeLabel(SourceKind kind) => switch (kind) {
  SourceKind.local => '本机已下载目录',
  SourceKind.openlist => 'OpenList / Alist API（网关）',
  SourceKind.synology => 'File Station API',
  SourceKind.navidrome => 'OpenSubsonic（音乐）',
  SourceKind.smb => 'SMB 共享目录',
  SourceKind.webdav => 'WebDAV',
  SourceKind.plex => 'Plex Token',
  SourceKind.jellyfin => 'Jellyfin API Key',
  SourceKind.emby => 'Emby API Key',
  _ => kind.name.toUpperCase(),
};
SourceProvider? providerById(String id) =>
    sourceProviders.where((p) => p.id == id).firstOrNull;
