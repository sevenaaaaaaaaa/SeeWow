class ParsedName {
  ParsedName({required this.title, this.showTitle, this.season, this.episode, this.year, this.quality = ''});
  final String title;
  final String? showTitle;
  final int? season;
  final int? episode;
  final int? year;
  final String quality;
}

class FilenameParser {
  static final _se = RegExp(r'[Ss](\d{1,2})[Ee](\d{1,3})');
  static final _x = RegExp(r'(?:^|[^a-zA-Z0-9])(\d{1,2})[xX](\d{1,3})(?:[^0-9]|$)');
  static final _cn = RegExp(r'第\s*(\d{1,3})\s*季.*?第\s*(\d{1,3})\s*集');
  static final _year = RegExp(r'(?<![0-9])(19\d{2}|20\d{2})(?![0-9])');
  static final _quality = RegExp(r'(2160p|1080p|720p|576p|480p|4k|uhd|hdr10\+?|dolby[ .]?vision|dv|bluray|blu-ray|web-?dl|webrip|remux)', caseSensitive: false);

  static final _stop = RegExp(r'\b(2160p|1080p|720p|480p|4k|uhd|hdr10\+?|dolby[ .]?vision|bluray|blu-ray|web-?dl|webrip|remux|x264|x265|h\.?264|h\.?265|hevc|av1|aac|dts|truehd|atmos|proper|repack|extended|imax|10bit|8bit)\b', caseSensitive: false);

  static ParsedName parse(String filename, {String? parentFolder}) {
    var name = filename;
    final dot = name.lastIndexOf('.');
    if (dot > 0) name = name.substring(0, dot);
    name = name.replaceAll('_', ' ').replaceAll('.', ' ');

    int? season;
    int? episode;
    String? show;

    final se = _se.firstMatch(name);
    if (se != null) {
      season = int.tryParse(se.group(1)!);
      episode = int.tryParse(se.group(2)!);
      show = _clean(name.substring(0, se.start));
    } else {
      final x = _x.firstMatch(name);
      if (x != null) {
        season = int.tryParse(x.group(1)!);
        episode = int.tryParse(x.group(2)!);
        show = _clean(name.substring(0, x.start));
      } else {
        final cn = _cn.firstMatch(name);
        if (cn != null) {
          season = int.tryParse(cn.group(1)!);
          episode = int.tryParse(cn.group(2)!);
          show = _clean(name.substring(0, cn.start));
        }
      }
    }

    int? year;
    final yearMatch = _year.allMatches(name).toList();
    if (yearMatch.isNotEmpty) year = int.tryParse(yearMatch.last.group(1)!);

    final qualities = <String>{};
    for (final m in _quality.allMatches(name)) {
      final token = m.group(1)!.toLowerCase();
      if (token.contains('2160') || token == '4k' || token == 'uhd') qualities.add('4K');
      else if (token.contains('1080')) qualities.add('1080p');
      else if (token.contains('720')) qualities.add('720p');
      else if (token.contains('dolby') || token == 'dv') qualities.add('Dolby Vision');
      else if (token.startsWith('hdr')) qualities.add('HDR');
      else if (token.contains('blu')) qualities.add('BluRay');
      else if (token.contains('web')) qualities.add('WEB');
      else if (token.contains('remux')) qualities.add('Remux');
    }

    String title;
    if (show != null && show.isNotEmpty) {
      title = show;
      if (season != null && episode != null) title = '$title  S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
      if (parentFolder != null) {
        final pf = _clean(parentFolder);
        if (pf.isNotEmpty && !pf.toLowerCase().contains(show.toLowerCase())) title = '$pf  $title';
      }
    } else {
      title = _clean(name);
      if (yearMatch.isNotEmpty) {
        final idx = name.lastIndexOf(yearMatch.last.group(1)!);
        final head = _clean(name.substring(0, idx));
        if (head.isNotEmpty) title = head;
      }
    }

    return ParsedName(
      title: title.isEmpty ? filename : title,
      showTitle: show?.isNotEmpty == true ? show : null,
      season: season,
      episode: episode,
      year: year,
      quality: qualities.join(' · '),
    );
  }

  static String _clean(String raw) {
    var s = raw.replaceAll(RegExp(r'[\[\](){}]'), ' ');
    s = s.replaceAll(_stop, ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    s = s.replaceAll(RegExp(r'[-–—]+\s*$'), '').trim();
    return s;
  }
}
