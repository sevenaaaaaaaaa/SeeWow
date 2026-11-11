class MetadataLanguage {
  const MetadataLanguage(this.tag, this.name, {this.region = ''});
  final String tag, name, region;
  static const regional = [
    MetadataLanguage('ja-JP', '日本語', region: 'JP'),
    MetadataLanguage('ko-KR', '한국어', region: 'KR'),
    MetadataLanguage('zh-HK', '香港繁體', region: 'HK'),
    MetadataLanguage('zh-TW', '台灣繁體', region: 'TW'),
    MetadataLanguage('ru-RU', 'Русский', region: 'RU'),
    MetadataLanguage('es-ES', 'Español', region: 'ES'),
    MetadataLanguage('ar-SA', 'العربية', region: 'SA'),
    MetadataLanguage('bo-CN', 'བོད་ཡིག', region: 'CN'),
  ];
  static const defaults = [
    'ja-JP',
    'ko-KR',
    'zh-HK',
    'zh-TW',
    'ru-RU',
    'es-ES',
    'ar-SA',
    'bo-CN',
  ];
  static String label(String tag) =>
      regional.where((p) => p.tag == tag).firstOrNull?.name ??
      switch (tag) {
        'zh-CN' => '简体中文',
        'en-US' => 'English',
        _ => tag,
      };
  static bool rtl(String tag) =>
      ['ar', 'fa', 'he', 'ur'].contains(tag.split('-').first);
  static String? font(String tag) => tag.startsWith('bo')
      ? 'NotoSerifTibetan'
      : rtl(tag)
      ? 'NotoSansArabic'
      : null;
}

/// Origins are tracked per field so filling a missing synopsis never relabels
/// an existing provider title as a machine translation.
class LocalizedMetadata {
  const LocalizedMetadata({
    this.title = '',
    this.overview = '',
    this.titleOrigin = 'source',
    this.overviewOrigin = 'source',
    this.provider = '',
    this.engine = '',
    this.sourceLanguage = '',
    this.inputHash = '',
    this.roles = const {},
  });
  final String title,
      overview,
      titleOrigin,
      overviewOrigin,
      provider,
      engine,
      sourceLanguage,
      inputHash;
  final Map<String, String> roles;
  bool get empty => title.isEmpty && overview.isEmpty && roles.isEmpty;
  bool get machine =>
      titleOrigin == 'machine' ||
      overviewOrigin == 'machine' ||
      roles.isNotEmpty;
  Map<String, dynamic> toJson() => {
    'title': title,
    'overview': overview,
    'titleOrigin': titleOrigin,
    'overviewOrigin': overviewOrigin,
    'provider': provider,
    'engine': engine,
    'sourceLanguage': sourceLanguage,
    'inputHash': inputHash,
    'roles': roles,
  };
  factory LocalizedMetadata.fromJson(Map<String, dynamic> j) =>
      LocalizedMetadata(
        title: j['title'] as String? ?? '',
        overview: j['overview'] as String? ?? '',
        titleOrigin: j['titleOrigin'] as String? ?? 'source',
        overviewOrigin: j['overviewOrigin'] as String? ?? 'source',
        provider: j['provider'] as String? ?? '',
        engine: j['engine'] as String? ?? '',
        sourceLanguage: j['sourceLanguage'] as String? ?? '',
        inputHash: j['inputHash'] as String? ?? '',
        roles: (j['roles'] as Map? ?? {}).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );
  LocalizedMetadata mergeSource(LocalizedMetadata source) => LocalizedMetadata(
    title: source.title.isEmpty ? title : source.title,
    overview: source.overview.isEmpty ? overview : source.overview,
    titleOrigin: source.title.isEmpty ? titleOrigin : source.titleOrigin,
    overviewOrigin: source.overview.isEmpty
        ? overviewOrigin
        : source.overviewOrigin,
    provider: source.provider.isEmpty ? provider : source.provider,
    engine: engine,
    sourceLanguage: sourceLanguage,
    inputHash: inputHash,
    roles: roles,
  );
}
