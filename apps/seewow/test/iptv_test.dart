import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/iptv.dart';

void main() {
  test('parses EXTINF attributes, groups and urls', () {
    const src = '#EXTM3U\n'
        '#EXTINF:-1 tvg-id="cctv1" tvg-name="CCTV-1" tvg-logo="http://logo/1.png" group-title="央视",CCTV-1 综合\n'
        'http://example.com/cctv1.m3u8\n'
        '#EXTINF:-1 group-title="卫视",湖南卫视\n'
        'http://example.com/hunan.m3u8\n'
        '#EXTGRP:体育\n'
        '#EXTINF:-1,五星体育\n'
        'http://example.com/sports.m3u8\n';
    final channels = M3UParser.parse(src, playlistId: 'p1');
    expect(channels.length, 3);
    expect(channels[0].name, 'CCTV-1 综合');
    expect(channels[0].group, '央视');
    expect(channels[0].logo, 'http://logo/1.png');
    expect(channels[1].name, '湖南卫视');
    expect(channels[2].group, '体育');
    final grouped = M3UParser.group(channels);
    expect(grouped.keys, containsAll(['央视', '卫视', '体育']));
  });

  test('ignores comments, blanks and non-url lines', () {
    const src = '#EXTM3U\n#EXTVLCOPT:network-caching=1000\nnot a url\n#EXTINF:-1,Only\nhttps://x/y.m3u8';
    final channels = M3UParser.parse(src, playlistId: 'p2');
    expect(channels.length, 1);
    expect(channels.single.name, 'Only');
    expect(channels.single.group, '未分组');
  });
}
