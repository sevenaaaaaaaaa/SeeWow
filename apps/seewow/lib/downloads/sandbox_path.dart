import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// iOS 应用沙盒里的绝对路径长这样：
///
///   /var/mobile/Containers/Data/Application/8A1B-…/Documents/SeeWow/a.mp4
///
/// 升级或重装之后 `8A1B-…` 这一段会换掉，于是所有存下来的绝对路径都指向
/// 不存在的位置——文件本体其实还在新容器的同一相对路径下。这里把「容器根
/// 之后的部分」取出来，重新挂到当前容器根上，而不是宣布文件被删了。
final _containerMarker = RegExp(r'/Application/[^/]+/(.+)$');

/// `Documents/SeeWow/a.mp4` 这样的容器内相对路径；不是容器路径就返回 null。
String? sandboxSuffix(String path) {
  final match = _containerMarker.firstMatch(path);
  if (match == null) return null;
  final suffix = match.group(1);
  return suffix == null || suffix.isEmpty ? null : suffix;
}

/// 当前容器根（Documents 的上一级）。取不到就返回 null，调用方按原样处理。
Future<Directory?> currentContainerRoot() async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(docs.path).parent;
  } catch (_) {
    return null;
  }
}

/// 把旧容器里的绝对路径换成当前容器里的等价路径。
///
/// 文件不在新位置就返回 null —— 那是真的没了，不要假装能找到。
Future<String?> relocateSandboxPath(
  String stored, {
  Directory? containerRoot,
}) async {
  final suffix = sandboxSuffix(stored);
  if (suffix == null) return null;
  final root = containerRoot ?? await currentContainerRoot();
  if (root == null) return null;
  final candidate = '${root.path}/$suffix';
  // 文件与下载目录都走这条换算：目录同样会因为容器 UUID 变化而失效。
  return File(candidate).existsSync() || Directory(candidate).existsSync()
      ? candidate
      : null;
}

/// 最后一道网：路径形状变了、容器也换了的极端情况。
///
/// 只在下载目录里找同名文件，而且**必须唯一**匹配 —— 同名的两份文件宁可
/// 认定失败，也不能把 A 片认成 B 片。
Future<String?> findByName(
  String stored, {
  required Directory root,
  int maxEntries = 20000,
}) async {
  final name = stored.split(RegExp(r'[\\/]')).lastWhere(
    (part) => part.isNotEmpty,
    orElse: () => '',
  );
  if (name.isEmpty || !await root.exists()) return null;
  var seen = 0;
  String? match;
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (++seen > maxEntries) return null;
    if (entity is! File) continue;
    if (entity.uri.pathSegments.last != name) continue;
    if (match != null) return null;
    match = entity.path;
  }
  return match;
}
