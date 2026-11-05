import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/filename_parser.dart';

void main() {
  group('FilenameParser', () {
    test('parses SxxExx episode names', () {
      final p = FilenameParser.parse('Dark S01E02 1080p WEB-DL x264.mkv', parentFolder: 'Dark');
      expect(p.showTitle, 'Dark');
      expect(p.season, 1);
      expect(p.episode, 2);
      expect(p.quality, contains('1080p'));
    });

    test('parses 1x02 style and chinese season/episode', () {
      final a = FilenameParser.parse('Severance 1x03 2160p.mkv');
      expect(a.season, 1);
      expect(a.episode, 3);
      expect(a.quality, contains('4K'));

      final b = FilenameParser.parse('某剧 第2季 第5集.mp4');
      expect(b.season, 2);
      expect(b.episode, 5);
    });

    test('parses movie title, year and quality tokens', () {
      final p = FilenameParser.parse('Dune Part Two (2024) 2160p HDR10 BluRay.mkv');
      expect(p.title.toLowerCase(), contains('dune part two'));
      expect(p.year, 2024);
      expect(p.quality, contains('4K'));
      expect(p.quality, contains('HDR'));
    });
  });
}
