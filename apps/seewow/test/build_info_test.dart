import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/app/build_info.dart';

void main() {
  test('BuildInfo 的默认版本必须与 pubspec 同步', () {
    // 1.18.0 修的就是「界面版本号写死」；这条测试防止它再次漂移。
    final raw = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+',
      multiLine: true,
    ).firstMatch(raw);
    expect(match, isNotNull, reason: 'pubspec.yaml 里应有 version: x.y.z+n');
    expect(BuildInfo.version, match!.group(1));
  });
}