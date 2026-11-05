class IPTVChannel {
  IPTVChannel({
    required this.id,
    required this.playlistId,
    required this.name,
    required this.url,
    this.logo = '',
    this.group = '未分组',
    this.tvgId = '',
  });

  final String id;
  final String playlistId;
  final String name;
  final String url;
  final String logo;
  final String group;
  final String tvgId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'playlistId': playlistId,
        'name': name,
        'url': url,
        'logo': logo,
        'group': group,
        'tvgId': tvgId,
      };

  factory IPTVChannel.fromJson(Map<String, dynamic> j) => IPTVChannel(
        id: j['id'] as String,
        playlistId: j['playlistId'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        logo: (j['logo'] as String?) ?? '',
        group: (j['group'] as String?) ?? '未分组',
        tvgId: (j['tvgId'] as String?) ?? '',
      );
}

class IPTVPlaylist {
  IPTVPlaylist({
    required this.id,
    required this.name,
    required this.source,
    this.channelCount = 0,
    this.updatedAt,
    this.epgUrl,
    this.epgCount = 0,
  });

  final String id;
  final String name;
  final String source;
  final int channelCount;
  final DateTime? updatedAt;
  final String? epgUrl;
  final int epgCount;

  IPTVPlaylist copyWith({int? channelCount, DateTime? updatedAt, String? epgUrl, int? epgCount}) => IPTVPlaylist(
        id: id,
        name: name,
        source: source,
        channelCount: channelCount ?? this.channelCount,
        updatedAt: updatedAt ?? this.updatedAt,
        epgUrl: epgUrl ?? this.epgUrl,
        epgCount: epgCount ?? this.epgCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'source': source,
        'channelCount': channelCount,
        'updatedAt': updatedAt?.toIso8601String(),
        'epgUrl': epgUrl,
        'epgCount': epgCount,
      };

  factory IPTVPlaylist.fromJson(Map<String, dynamic> j) => IPTVPlaylist(
        id: j['id'] as String,
        name: j['name'] as String,
        source: j['source'] as String,
        channelCount: (j['channelCount'] as num?)?.toInt() ?? 0,
        updatedAt: j['updatedAt'] != null ? DateTime.tryParse(j['updatedAt'] as String) : null,
        epgUrl: j['epgUrl'] as String?,
        epgCount: (j['epgCount'] as num?)?.toInt() ?? 0,
      );
}

/// M3U / M3U8 channel-list parser. It tolerates the usual messy exports:
/// attribute order, missing tvg-* fields, #EXTGRP group markers and comments.
class M3UParser {
  static final _attr = RegExp(r'([a-zA-Z0-9\-]+)="([^"]*)"');
  static final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+\-.]*://');

  static List<IPTVChannel> parse(String text, {required String playlistId}) {
    final channels = <IPTVChannel>[];
    final lines = text.split(RegExp(r'\r?\n'));
    Map<String, String> attrs = const {};
    String pendingName = '';
    String pendingGroup = '';
    var index = 0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF')) {
        final comma = line.indexOf(',');
        final meta = comma >= 0 ? line.substring(0, comma) : line;
        final tail = comma >= 0 ? line.substring(comma + 1).trim() : '';
        attrs = {for (final m in _attr.allMatches(meta)) m.group(1)!.toLowerCase(): m.group(2) ?? ''};
        pendingName = tail.isNotEmpty ? tail : (attrs['tvg-name'] ?? '');
        // EXTGRP may precede this EXTINF; only override when the line sets a group.
        pendingGroup = attrs['group-title'] ?? pendingGroup;
        continue;
      }
      if (line.startsWith('#EXTGRP')) {
        pendingGroup = line.substring(line.indexOf(':') + 1).trim();
        continue;
      }
      if (line.startsWith('#')) continue;
      if (!_scheme.hasMatch(line)) continue;
      final name = pendingName.isNotEmpty ? pendingName : '频道 ' + (index + 1).toString();
      channels.add(IPTVChannel(
        id: playlistId + '-' + index.toString().padLeft(4, '0'),
        playlistId: playlistId,
        name: name,
        url: line,
        logo: attrs['tvg-logo'] ?? '',
        group: pendingGroup.isEmpty ? '未分组' : pendingGroup,
        tvgId: attrs['tvg-id'] ?? '',
      ));
      index++;
      attrs = const {};
      pendingName = '';
      pendingGroup = '';
    }
    return channels;
  }

  /// Groups channels by their group-title while keeping the playlist order.
  static Map<String, List<IPTVChannel>> group(List<IPTVChannel> channels) {
    final out = <String, List<IPTVChannel>>{};
    for (final c in channels) {
      out.putIfAbsent(c.group, () => []).add(c);
    }
    return out;
  }
}
