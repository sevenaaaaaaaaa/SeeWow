import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../domain/online_source.dart';

/// 「在线源」站点清单的持久化。只存站点地址与开关，不存任何凭据。
class OnlineSourceStore extends ChangeNotifier {
  OnlineSourceStore({Directory? directory}) : _override = directory;

  /// 只放在内存里：测试用，不碰磁盘。
  OnlineSourceStore.empty()
    : _override = null,
      _inMemory = true;

  /// 随包内置的源包。改这个 JSON 就能换包，不必改代码。
  static const builtinPack = 'assets/sources/builtin_sources.json';

  final Directory? _override;
  bool _inMemory = false;
  final List<OnlineSite> sites = [];
  bool loading = false;
  String? toast;

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
        ..addAll(dedupeSites(seedOnlineSites));
      loading = false;
      notifyListeners();
      return;
    }
    try {
      final file = await _file();
      final existed = await file.exists();
      if (existed) {
        final raw = jsonDecode(await file.readAsString());
        final list = raw is Map ? raw['sites'] : null;
        if (list is List) {
          sites
            ..clear()
            ..addAll(list.map(OnlineSite.fromJson).whereType<OnlineSite>());
        }
      }
      // 首次启动（还没有本地清单）先认内置源包；读不到才回落到代码里的种子。
      if (!existed) sites.addAll(await _readBuiltinPack());
      if (sites.isEmpty) sites.addAll(seedOnlineSites);
      final unique = dedupeSites(sites);
      sites
        ..clear()
        ..addAll(unique);
      if (!existed) await save();
    } catch (_) {
      sites
        ..clear()
        ..addAll(dedupeSites(seedOnlineSites));
      toast = '在线源清单读取失败，已回到默认站点';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 读随包内置的站点清单。任何失败都返回空，交给调用方回落，不抛给界面。
  Future<List<OnlineSite>> _readBuiltinPack() async {
    if (_inMemory) return const [];
    try {
      // 源包是加分项，不是启动门槛：读不到（旧包、测试环境、插件异常）
      // 就当作空，让调用方回落到代码里的种子，绝不让启动卡在这里。
      final text = await rootBundle
          .loadString(builtinPack)
          .timeout(const Duration(milliseconds: 750), onTimeout: () => '');
      if (text.isEmpty) return const [];
      final raw = jsonDecode(text);
      final list = raw is Map ? raw['sites'] : null;
      if (list is! List) return const [];
      return dedupeSites(list.map(OnlineSite.fromJson).whereType<OnlineSite>());
    } catch (_) {
      return const [];
    }
  }

  Future<void> save() async {
    if (_inMemory) return;
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
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
