import 'dart:io';

/// 一个「解析组件」= 把不能直接播放的页面变成可播地址的一种手段。
///
/// 统一登记在这里，是为了让「用什么代价换什么覆盖率」这件事只有一个出处：
/// 谁执行远端脚本、谁只读直链、在哪些平台可用，界面上据此显示与开关。
enum ParseCapability { directMedia, pageExtract, webExtract }

class ParseComponent {
  const ParseComponent({
    required this.id,
    required this.name,
    required this.summary,
    required this.capability,
    required this.executesRemoteScripts,
    this.platforms = const {'ios', 'android'},
  });

  final String id;
  final String name;
  final String summary;
  final ParseCapability capability;

  /// 是否会在本机执行对方页面的脚本。true 的组件必须逐次确认。
  final bool executesRemoteScripts;
  final Set<String> platforms;

  bool get runsHere => platforms.contains(Platform.operatingSystem);
}

const parseComponents = <ParseComponent>[
  ParseComponent(
    id: 'direct',
    name: '直链播放',
    summary: 'm3u8 / mp4 / flv 直接交给播放器，不加载任何网页。',
    capability: ParseCapability.directMedia,
    executesRemoteScripts: false,
    platforms: {'ios', 'android', 'macos', 'windows', 'linux'},
  ),
  ParseComponent(
    id: 'static',
    name: '静态解析（读页面源码）',
    summary: '直接取分享页 HTML，从文本里找 m3u8；不执行页面脚本，任何平台都能用。',
    capability: ParseCapability.pageExtract,
    executesRemoteScripts: false,
    platforms: {'ios', 'android', 'macos', 'windows', 'linux'},
  ),
  ParseComponent(
    id: 'webview',
    name: '网页解析（WebView）',
    summary: '在隔离 WebView 里打开分享页，抓它自己请求的 m3u8。会执行该页面的第三方脚本。',
    capability: ParseCapability.webExtract,
    executesRemoteScripts: true,
  ),
];

ParseComponent? parseComponent(String id) {
  for (final component in parseComponents) {
    if (component.id == id) return component;
  }
  return null;
}

/// 当前平台上可用的解析组件，按「代价从低到高」排。
List<ParseComponent> availableParsers() => [
  for (final component in parseComponents)
    if (component.runsHere) component,
];
