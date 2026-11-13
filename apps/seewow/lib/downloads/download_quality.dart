import '../domain/media_item.dart';

class DownloadQuality {
  const DownloadQuality({
    required this.id,
    required this.label,
    this.width = 0,
    this.height = 0,
    this.bitrateKbps = 0,
  });

  final String id;
  final String label;
  final int width;
  final int height;
  final int bitrateKbps;

  bool get isOriginal => id == 'original';
}

const originalQuality = DownloadQuality(id: 'original', label: '原始画质（直连文件）');

const _qualities = [
  originalQuality,
  DownloadQuality(
    id: '1080p',
    label: '1080p · 约 8 Mbps',
    width: 1920,
    height: 1080,
    bitrateKbps: 8000,
  ),
  DownloadQuality(
    id: '720p',
    label: '720p · 约 4 Mbps',
    width: 1280,
    height: 720,
    bitrateKbps: 4000,
  ),
  DownloadQuality(
    id: '480p',
    label: '480p · 约 1.5 Mbps',
    width: 854,
    height: 480,
    bitrateKbps: 1500,
  ),
];

/// Plex / Emby can transcode server-side; other sources only expose the
/// original file.
List<DownloadQuality> downloadQualitiesFor(MediaSource? source) {
  final kind = source?.kind;
  if (kind == SourceKind.plex ||
      kind == SourceKind.emby ||
      kind == SourceKind.jellyfin) {
    return _qualities;
  }
  return const [originalQuality];
}

DownloadQuality qualityById(String id) =>
    _qualities.where((q) => q.id == id).firstOrNull ?? originalQuality;

/// Builds a server-side transcode URL for Plex / Emby. Returns null when the
/// source should be downloaded as-is.
String? buildQualityLocator(
  MediaItem item,
  MediaSource? source,
  String qualityId,
) {
  if (qualityId == 'original' || source == null) return null;
  final base = Uri.tryParse(item.locator);
  if (base == null || base.host.isEmpty) return null;
  final quality = qualityById(qualityId);
  final rawId = item.id.split(':').last;
  final origin = Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
  );
  if (source.kind == SourceKind.emby || source.kind == SourceKind.jellyfin) {
    return origin
        .replace(
          path: '/Videos/${Uri.encodeComponent(rawId)}/stream.mp4',
          queryParameters: {
            'Static': 'false',
            'VideoCodec': 'h264',
            'AudioCodec': 'aac',
            'VideoBitrate': '${quality.bitrateKbps * 1000}',
            'AudioBitrate': '128000',
            'MaxWidth': '${quality.width}',
            'MaxHeight': '${quality.height}',
          },
        )
        .toString();
  }
  if (source.kind == SourceKind.plex) {
    return origin
        .replace(
          path: '/video/:/transcode/universal/start.m3u8',
          queryParameters: {
            'path': '/library/metadata/$rawId',
            'mediaIndex': '0',
            'partIndex': '0',
            'protocol': 'hls',
            'fastSeek': '1',
            'directPlay': '0',
            'directStream': '1',
            'copyts': '1',
            'maxVideoBitrate': '${quality.bitrateKbps}',
            'videoResolution': '${quality.width}x${quality.height}',
            'session': 'seewow-${DateTime.now().millisecondsSinceEpoch}',
            'X-Plex-Client-Identifier': 'seewow',
            'X-Plex-Product': 'SeeWow',
          },
        )
        .toString();
  }
  return null;
}
