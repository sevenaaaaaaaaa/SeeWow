import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../domain/online_source.dart';

/// 「在线源」站点清单的持久化。只存站点地址与开关，不存任何凭据。
class OnlineSourceStore extends ChangeNotifier {
  OnlineSourceStore({Directory? directory, bool? noBuiltinSources})
    : _override = directory,
      noBuiltinSources = noBuiltinSources ?? _noBuiltinSourcesDefault;

  /// 只放在内存里：测试用，不碰磁盘。
  OnlineSourceStore.empty({bool? noBuiltinSources})
    : _override = null,
      _inMemory = true,
      noBuiltinSources = noBuiltinSources ?? _noBuiltinSourcesDefault;

  /// 公开分发包（上 GitHub 那一份）不随包带任何站点：既不打源包，也不铺代码里的
  /// 种子。本地预览包、IPA、iCloud 那份照常带源。由构建参数决定：
  ///
  /// ```sh
  /// flutter build macos --release --dart-define=SEEWOW_NO_BUILTIN_SOURCES=true
  /// ```
  static const _noBuiltinSourcesDefault = bool.fromEnvironment(
    'SEEWOW_NO_BUILTIN_SOURCES',
  );

  /// 随包内置的源包。改这个 JSON 就能换包，不必改代码。
  static const builtinPack = 'assets/sources/builtin_sources.json';

  /// 本地清单里记的源包版本。没有这个字段的文件是 v1 时代写的。
  static const packVersionKey = 'packVersion';

  /// v1 随包发过、v2 已经换掉的站点 id。
  ///
  /// 装过 v1 的机器本地清单早就存在，按「有本地清单就不再铺包」的规则会一直
  /// 留着那 9 个连不上的站。迁移只按这批 id 精确剔除，`custom-*`（用户自己加
  /// 的）和从 TVBox 配置导入的站一条都不动。
  static const legacyBuiltinIds = <String>{
    'dytt',
    'tyys',
    'lzi',
    'sony',
    'wolong',
    'jisu',
    'uku',
    'jianan',
    'jinchan',
    'xiaomianyang',
    'lv',
    'bfzy',
  };

  /// 这份构建是否随包带内置站点。true 时源包与代码种子都不生效。
  final bool noBuiltinSources;

  final Directory? _override;
  bool _inMemory = false;
  final List<OnlineSite> sites = [];
  bool loading = false;
  String? toast;

  /// 当前清单用的是哪一版源包，落盘时一起写。
  String _packVersion = '1';

  Future<Directory> _dir() async =>
      _override ?? await getApplicationSupportDirectory();

  Future<File> _file() async {
    final dir = await _dir();
    await dir.create(recursive: true);
    return File('${dir.path}/online_sources.json');
  }

  List<OnlineSite> get enabledSites =>
      sites.where((site) => site.enabled).toList(growable: false);

  Future<void> load() async {
    loading = true;
    notifyListeners();
    if (_inMemory) {
      sites
        ..clear()
        ..addAll(noBuiltinSources ? const <OnlineSite>[] : dedupeSites(seedOnlineSites));
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final file = await _file();
      final existed = await file.exists();
      String? storedPack;
      if (existed) {
        final raw = jsonDecode(await file.readAsString());
        final list = raw is Map ? raw['sites'] : null;
        if (raw is Map) storedPack = raw[packVersionKey]?.toString();
        if (list is List) {
          sites
            ..clear()
            ..addAll(list.map(OnlineSite.fromJson).whereType<OnlineSite>());
        }
      }
      final pack = await _readBuiltinPack();
      var dirty = !existed;
      if (!existed) {
        sites.addAll(pack.sites);
      } else if (pack.sites.isNotEmpty && storedPack != pack.version) {
        // 源包换过版本：把 v1 那批内置站点换成本版，用户的站点一条不动。
        sites.removeWhere((site) => legacyBuiltinIds.contains(site.id));
        sites.addAll(pack.sites);
        dirty = true;
        toast = '内置源包已更新（${pack.sites.length} 个站点）';
      }
      if (pack.version != null) _packVersion = pack.version!;
      // 公开包不带任何站点；本地包读不到源包时才回落到代码种子。
      if (sites.isEmpty && !noBuiltinSources) sites.addAll(seedOnlineSites);
      final unique = dedupeSites(sites);
      sites
        ..clear()
        ..addAll(unique);
      if (dirty) await save();
    } catch (_) {
      sites
        ..clear()
        ..addAll(noBuiltinSources ? const <OnlineSite>[] : dedupeSites(seedOnlineSites));
      toast = noBuiltinSources ? null : '在线源清单读取失败，已回到默认站点';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 读随包内置的站点清单。任何失败都返回空清单 + 空版本号，交给调用方回落，
  /// 不抛给界面。
  Future<({List<OnlineSite> sites, String? version})> _readBuiltinPack() async {
    if (_inMemory || noBuiltinSources) {
      return (sites: const <OnlineSite>[], version: null);
    }
    try {
      // 源包是加分项，不是启动门槛：读不到（旧包、测试环境、插件异常）
      // 就当作空，让调用方回落到代码里的种子，绝不让启动卡在这里。
      final text = await rootBundle
          .loadString(builtinPack)
          .timeout(const Duration(milliseconds: 750), onTimeout: () => '');
      if (text.isEmpty) return (sites: const <OnlineSite>[], version: null);
      final raw = jsonDecode(text);
      final list = raw is Map ? raw['sites'] : null;
      if (list is! List) return (sites: const <OnlineSite>[], version: null);
      final version = raw is Map ? raw[packVersionKey]?.toString() : null;
      return (
        sites: dedupeSites(list.map(OnlineSite.fromJson).whereType<OnlineSite>()),
        version: version,
      );
    } catch (_) {
      return (sites: const <OnlineSite>[], version: null);
    }
  }

  Future<void> save() async {
    if (_inMemory) return;
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          packVersionKey: _packVersion,
          'sites': [for (final site in sites) site.toJson()],
        }),
      );
    } catch (_) {
      toast = '站点清单保存失败';
    }
  }

  /// 添加一个采集站；地址必须是 http(s)，同接口只留一个。
  Future<bool> addSite(String name, String api) async {
    final trimmed = api.trim();
    final label = name.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      toast = '采集站地址要填完整的 http(s) 接口地址';
      notifyListeners();
      return false;
    }
    final site = OnlineSite(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      name: label.isEmpty ? uri.host : label,
      api: trimmed,
    );
    if (sites.any((existing) => existing.hostKey == site.hostKey)) {
      toast = '这个接口已经在清单里了';
      notifyListeners();
      return false;
    }
    sites.add(site);
    toast = '已加入「${site.name}」';
    await save();
    notifyListeners();
    return true;
  }

  /// 从一份 TVBox 配置里挑出能直连的采集站；返回新增数量。
  Future<int> importFromConfig(List<OnlineSite> candidates) async {
    var added = 0;
    for (final candidate in candidates) {
      if (sites.any((existing) => existing.hostKey == candidate.hostKey)) {
        continue;
      }
      sites.add(candidate);
      added++;
    }
    if (added > 0) await save();
    notifyListeners();
    return added;
  }

  /// 一次开关全部站点（离线批量操作只写一次盘）。
  Future<int> setAll(bool enabled) async {
    var changed = 0;
    for (var i = 0; i < sites.length; i++) {
      if (sites[i].enabled == enabled) continue;
      sites[i] = sites[i].copyWith(enabled: enabled);
      changed++;
    }
    if (changed > 0) {
      await save();
      notifyListeners();
    }
    return changed;
  }

  Future<void> removeSite(OnlineSite site) async {
    sites.removeWhere((existing) => existing.id == site.id);
    await save();
    notifyListeners();
  }

  Future<void> toggle(OnlineSite site, bool enabled) async {
    final index = sites.indexWhere((existing) => existing.id == site.id);
    if (index < 0) return;
    sites[index] = sites[index].copyWith(enabled: enabled);
    await save();
    notifyListeners();
  }
}
