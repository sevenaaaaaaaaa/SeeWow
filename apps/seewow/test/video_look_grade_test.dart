import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/playback/video_look.dart';

/// 画风就是一张 4x5 颜色矩阵（再加可选叠层），所以它可以被当成纯函数检验：
/// 给定一个像素，算出它变成什么。这里钉的就是「六款新画风各自做了什么」。
List<double> apply(List<double> m, List<double> rgb) {
  final a = rgb.length > 3 ? rgb[3] : 255.0;
  return [
    m[0] * rgb[0] + m[1] * rgb[1] + m[2] * rgb[2] + m[3] * a + m[4],
    m[5] * rgb[0] + m[6] * rgb[1] + m[7] * rgb[2] + m[8] * a + m[9],
    m[10] * rgb[0] + m[11] * rgb[1] + m[12] * rgb[2] + m[13] * a + m[14],
  ].map((v) => v.clamp(0.0, 255.0)).toList();
}

double luma(List<double> c) => .2126 * c[0] + .7152 * c[1] + .0722 * c[2];

const skin = [222.0, 173.0, 141.0];
const midGray = [128.0, 128.0, 128.0];

final added = ['coolwhite', 'pinkwhite', 'guoman', 'riiman', 'meiman', 'kon'];

void main() {
  test('每一款画风都是合法的 4x5 矩阵，alpha 行不动', () {
    for (final look in VideoLook.presets) {
      expect(look.matrix.length, 20, reason: '${look.id} 的矩阵长度');
      for (var i = 0; i < look.matrix.length; i++) {
        final v = look.matrix[i];
        expect(v.isFinite, isTrue, reason: '${look.id} 出现非有限值');
        if (i % 5 == 4) {
          // 第五列是 0–255 空间的偏置：±60 已经相当于 ±23% 的提降。
          expect(v.abs(), lessThan(60), reason: '${look.id} 的偏置过大');
        } else {
          expect(v.abs(), lessThan(3), reason: '${look.id} 的系数超出常用范围');
        }
      }
      expect(look.matrix.sublist(15), [
        0,
        0,
        0,
        1,
        0,
      ], reason: '${look.id} 动了 alpha');
    }
  });

  test('原色是恒等：任何像素都不变', () {
    expect(apply(VideoLook.native.matrix, skin), skin);
    expect(apply(VideoLook.native.matrix, midGray), midGray);
  });

  test('六款新画风在取样板上互不相同，不是换皮', () {
    // 只看肤色会冤枉「粉白 vs 国漫」——两者的差别在天空和暗部，所以整块板比。
    const board = [
      skin,
      [120.0, 170.0, 220.0],
      [70.0, 120.0, 60.0],
      [30.0, 34.0, 42.0],
    ];
    final outputs = <String, List<List<double>>>{
      for (final id in added)
        id: [for (final c in board) apply(VideoLook.byId(id).matrix, c)],
    };
    for (var i = 0; i < added.length; i++) {
      for (var j = i + 1; j < added.length; j++) {
        var diff = 0.0;
        for (var n = 0; n < board.length; n++) {
          final a = outputs[added[i]]![n], b = outputs[added[j]]![n];
          diff = math.max(
            diff,
            [for (var k = 0; k < 3; k++) (a[k] - b[k]).abs()].reduce(math.max),
          );
        }
        expect(diff, greaterThan(14), reason: '${added[i]} 与 ${added[j]} 太像');
      }
    }
  });

  test('冷白更亮更冷，粉白更亮更红', () {
    final base = apply(VideoLook.native.matrix, skin);
    final cool = apply(VideoLook.byId('coolwhite').matrix, skin);
    final pink = apply(VideoLook.byId('pinkwhite').matrix, skin);

    expect(luma(cool), greaterThan(luma(base) + 2), reason: '冷白要提亮');
    expect(
      cool[2] - cool[0],
      greaterThan(base[2] - base[0] + 2),
      reason: '冷白要往冷里推',
    );
    expect(luma(pink), greaterThan(luma(base) + 2), reason: '粉白要提亮');
    expect(
      pink[0] - pink[1],
      greaterThan(base[0] - base[1] + 2),
      reason: '粉白要更红',
    );
  });

  test('中灰不会被染成彩色', () {
    for (final id in added) {
      final out = apply(VideoLook.byId(id).matrix, midGray);
      for (final v in out) {
        expect((v - 128).abs(), lessThan(45), reason: '$id 把中灰推成了彩色');
      }
    }
  });

  test('美漫把黑位压得比原色更低', () {
    const dark = [40.0, 40.0, 40.0];
    final base = apply(VideoLook.native.matrix, dark);
    final bold = apply(VideoLook.byId('meiman').matrix, dark);
    expect(luma(bold), lessThan(luma(base)), reason: '美漫该压黑而不是抬黑');
  });

  test('未知 id 退回原色，不崩', () {
    expect(VideoLook.byId('nope').id, 'native');
    expect(VideoLook.byId(null).id, 'native');
  });
}
