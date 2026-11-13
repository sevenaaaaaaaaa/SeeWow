import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/downloads/download_quality.dart';

MediaSource _source(SourceKind kind, String location) =>
    MediaSource(id: 's', kind: kind, name: 'server', location: location);

MediaItem _item(String id, String locator) => MediaItem(
  id: id,
  sourceId: 's',
  kind: MediaKind.movie,
  title: 'Dune',
  locator: locator,
);

void main() {
  test('plex quality builds an HLS transcode URL', () {
    final locator = buildQualityLocator(
      _item('s:123', 'http://host:32400/library/parts/9/file.mkv'),
      _source(SourceKind.plex, 'http://host:32400'),
      '720p',
    );
    expect(locator, isNotNull);
    final uri = Uri.parse(locator!);
    expect(uri.path, '/video/:/transcode/universal/start.m3u8');
    expect(uri.queryParameters['path'], '/library/metadata/123');
    expect(uri.queryParameters['maxVideoBitrate'], '4000');
    expect(uri.queryParameters['videoResolution'], '1280x720');
    expect(uri.queryParameters['protocol'], 'hls');
  });

  test('emby quality builds a progressive mp4 transcode URL', () {
    final locator = buildQualityLocator(
      _item('s:456', 'https://nas:8096/Videos/456/stream?static=true'),
      _source(SourceKind.emby, 'https://nas:8096'),
      '1080p',
    );
    expect(locator, isNotNull);
    final uri = Uri.parse(locator!);
    expect(uri.path, '/Videos/456/stream.mp4');
    expect(uri.queryParameters['Static'], 'false');
    expect(uri.queryParameters['VideoBitrate'], '8000000');
    expect(uri.queryParameters['MaxWidth'], '1920');
  });

  test('original quality and local sources stay untouched', () {
    final item = _item('s:1', 'http://host/file.mkv');
    expect(
      buildQualityLocator(
        item,
        _source(SourceKind.plex, 'http://host'),
        'original',
      ),
      isNull,
    );
    expect(
      buildQualityLocator(
        _item('s:1', 'file:///tmp/a.mkv'),
        _source(SourceKind.local, '/tmp'),
        '720p',
      ),
      isNull,
    );
  });

  test('qualities are offered only for Plex / Emby', () {
    expect(
      downloadQualitiesFor(_source(SourceKind.plex, 'http://h')).length,
      4,
    );
    expect(
      downloadQualitiesFor(_source(SourceKind.emby, 'http://h')).length,
      4,
    );
    expect(
      downloadQualitiesFor(_source(SourceKind.webdav, 'http://h')).length,
      1,
    );
    expect(downloadQualitiesFor(null).single.id, 'original');
  });
}
