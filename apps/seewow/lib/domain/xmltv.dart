/// A single XMLTV programme entry.
class EPGProgram {
  EPGProgram({
    required this.channelId,
    required this.title,
    this.subtitle = '',
    this.description = '',
    required this.start,
    required this.stop,
  });

  final String channelId;
  final String title;
  final String subtitle;
  final String description;
  final DateTime start;
  final DateTime stop;

  double progressAt(DateTime now) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    return (now.difference(start).inSeconds / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
        'channelId': channelId,
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'start': start.toIso8601String(),
        'stop': stop.toIso8601String(),
      };

  factory EPGProgram.fromJson(Map<String, dynamic> j) => EPGProgram(
        channelId: j['channelId'] as String,
        title: j['title'] as String,
        subtitle: (j['subtitle'] as String?) ?? '',
        description: (j['description'] as String?) ?? '',
        start: DateTime.parse(j['start'] as String),
        stop: DateTime.parse(j['stop'] as String),
      );
}

/// Minimal but tolerant XMLTV parser: hand-rolled because the format is huge,
/// often malformed, and we only need programme time ranges per channel.
class XMLTVParser {
  static final _programme = RegExp(r'<programme\b([^>]*)>([\s\S]*?)</programme>', caseSensitive: false);
  static final _attr = RegExp(r'([a-zA-Z0-9\-_]+)="([^"]*)"');
  static final _title = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false);
  static final _subTitle = RegExp(r'<sub-title[^>]*>([\s\S]*?)</sub-title>', caseSensitive: false);
  static final _desc = RegExp(r'<desc[^>]*>([\s\S]*?)</desc>', caseSensitive: false);
  static final _time = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?$');

  static List<EPGProgram> parse(String xml, {DateTime? now}) {
    final out = <EPGProgram>[];
    for (final m in _programme.allMatches(xml)) {
      final attrs = {for (final a in _attr.allMatches(m.group(1)!)) a.group(1)!.toLowerCase(): a.group(2) ?? ''};
      final channelId = attrs['channel'] ?? '';
      if (channelId.isEmpty) continue;
      final body = m.group(2)!;
      final start = _parseTime(attrs['start'] ?? '');
      final stop = _parseTime(attrs['stop'] ?? '');
      if (start == null || stop == null || !stop.isAfter(start)) continue;
      final title = _clean(_title.firstMatch(body)?.group(1) ?? '');
      if (title.isEmpty) continue;
      out.add(EPGProgram(
        channelId: channelId,
        title: title,
        subtitle: _clean(_subTitle.firstMatch(body)?.group(1) ?? ''),
        description: _clean(_desc.firstMatch(body)?.group(1) ?? ''),
        start: start,
        stop: stop,
      ));
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  /// Groups programmes per XMLTV channel id, dropping anything older than
  /// [keepPast] so a five-day guide does not bloat the JSON store.
  static Map<String, List<EPGProgram>> group(List<EPGProgram> programs, {Duration keepPast = const Duration(hours: 12)}) {
    final cutoff = DateTime.now().subtract(keepPast);
    final out = <String, List<EPGProgram>>{};
    for (final p in programs) {
      if (p.stop.isBefore(cutoff)) continue;
      out.putIfAbsent(p.channelId, () => []).add(p);
    }
    for (final list in out.values) {
      list.sort((a, b) => a.start.compareTo(b.start));
    }
    return out;
  }

  static DateTime? _parseTime(String value) {
    final m = _time.firstMatch(value.trim());
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = m.group(6) != null ? int.parse(m.group(6)!) : 0;
    final offset = m.group(7);
    var offsetMinutes = 0;
    if (offset != null) {
      final sign = offset.startsWith('-') ? -1 : 1;
      offsetMinutes = sign * (int.parse(offset.substring(1, 3)) * 60 + int.parse(offset.substring(3, 5)));
    }
    final utc = DateTime.utc(year, month, day, hour, minute, second).subtract(Duration(minutes: offsetMinutes));
    return utc.toLocal();
  }

  static String _clean(String raw) {
    var text = raw.replaceAll(RegExp(r'<[^>]*>'), ' ');
    text = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
