/// 构建信息：版本号与构建戳。
///
/// 为什么不用 package_info：它要引一个插件、多一套原生依赖，只为读两个字符串，
/// 而这两个字符串在构建时就已经确定。构建脚本通过 `--dart-define` 传进来：
///
/// ```sh
/// flutter build macos --release \
///   --dart-define=SEEWOW_VERSION=1.20.1 \
///   --dart-define=SEEWOW_BUILD_STAMP="92443f8 2026-11-14T22:55"
/// ```
///
/// 没有传（比如 `flutter run`）时回落到 `dev`，界面上会明说这是开发构建，
/// 不会假装自己是某个正式版本。
class BuildInfo {
  const BuildInfo._();

  /// 语义版本号，不带 build number。来源是构建参数，默认值与 pubspec 同步。
  static const String version = String.fromEnvironment(
    'SEEWOW_VERSION',
    defaultValue: '1.20.1',
  );

  /// 构建戳：`<git commit 短哈希> <构建时间>`。
  static const String stamp = String.fromEnvironment(
    'SEEWOW_BUILD_STAMP',
    defaultValue: 'dev',
  );

  /// 关于页显示的一行：`1.18.0 (dev)` 或 `1.18.0 · 92443f8 · 2026-11-14T22:55`。
  static String get label => isDev ? '$version (dev)' : '$version · $stamp';

  static bool get isDev => stamp == 'dev' || stamp.isEmpty;
}
