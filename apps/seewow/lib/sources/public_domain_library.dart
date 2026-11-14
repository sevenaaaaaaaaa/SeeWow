import '../domain/media_item.dart';

/// A tiny starter library that needs no account, no token and no local file.
///
/// Only titles that are unambiguously free to redistribute are included:
/// Blender's open movies (CC BY) and films that have entered the public
/// domain. Every URL below was checked to answer HTTP 200 on 2026-11-14, and
/// each entry keeps its licence and credit visible in the UI, so a user always
/// knows why a title is here.
///
/// These items deliberately have no [MediaSource] behind them: playback hands
/// the plain https URL to libmpv, and a library refresh never touches them.
class PublicDomainTitle {
  const PublicDomainTitle({
    required this.id,
    required this.title,
    required this.year,
    required this.overview,
    required this.streamUrl,
    required this.posterUrl,
    required this.licence,
    required this.credit,
    required this.genres,
    this.quality = '1080p',
  });

  final String id, title, overview, streamUrl, posterUrl, licence, credit;
  final int year;
  final List<String> genres;
  final String quality;
}

const publicDomainTitles = <PublicDomainTitle>[
  PublicDomainTitle(
    id: 'pd-big-buck-bunny',
    title: '大雄兔',
    year: 2008,
    overview: 'Blender 基金会的开放电影：一只大兔子被三只啮齿动物欺负，决定反击。'
        '全片由开源工具制作，用于展示开放动画的工业级可能。',
    streamUrl:
        'https://archive.org/download/BigBuckBunny_124/Content/big_buck_bunny_720p_surround.mp4',
    posterUrl: 'https://archive.org/services/img/BigBuckBunny_124',
    licence: 'CC BY 3.0',
    credit: 'Blender Foundation',
    genres: ['动画', '喜剧'],
  ),
  PublicDomainTitle(
    id: 'pd-elephants-dream',
    title: '大象之梦',
    year: 2006,
    overview: 'Blender 的第一部开放电影。两个人在巨大机械世界里行走，'
        '讨论感知与真实——更像一首会动的诗，而不是一个故事。',
    streamUrl: 'https://archive.org/download/ElephantsDream/ed_1024_512kb.mp4',
    posterUrl: 'https://archive.org/services/img/ElephantsDream',
    licence: 'CC BY 2.5',
    credit: 'Blender Foundation',
    genres: ['动画', '科幻'],
    quality: '540p',
  ),
  PublicDomainTitle(
    id: 'pd-sintel',
    title: '辛特尔',
    year: 2010,
    overview: 'Blender 开放电影。少女穿越荒原寻找失散的幼龙，'
        '一段关于失去与放手的短片。',
    streamUrl: 'https://archive.org/download/Sintel/sintel-2048-surround.mp4',
    posterUrl: 'https://archive.org/services/img/Sintel',
    licence: 'CC BY 3.0',
    credit: 'Blender Foundation',
    genres: ['动画', '奇幻', '冒险'],
  ),
  PublicDomainTitle(
    id: 'pd-nosferatu',
    title: '诺斯费拉图',
    year: 1922,
    overview: '德国表现主义默片，影史上最早留存的吸血鬼电影之一。'
        '已进入公共领域，是默片恐怖片的起点。',
    streamUrl:
        'https://archive.org/download/nosferatu_1922/nosferatu_1922_512kb.mp4',
    posterUrl: 'https://archive.org/services/img/nosferatu_1922',
    licence: '公共领域',
    credit: 'Internet Archive',
    genres: ['恐怖', '默片'],
    quality: '480p',
  ),
  PublicDomainTitle(
    id: 'pd-his-girl-friday',
    title: '女友礼拜五',
    year: 1940,
    overview: '好莱坞神经喜剧代表作：报社主编想留住要离职的前妻兼首席记者，'
        '用一桩死刑新闻当筹码。语速极快的对白是它的招牌。',
    streamUrl:
        'https://archive.org/download/HisGirlFriday1940/seqhisgirlfridayfull1d_512kb.mp4',
    posterUrl: 'https://archive.org/services/img/HisGirlFriday1940',
    licence: '公共领域',
    credit: 'Internet Archive',
    genres: ['喜剧', '爱情'],
    quality: '480p',
  ),
];

const publicDomainSourceId = 'public-domain';

/// Turns the catalogue into library items. Ids are stable, so loading the
/// sample twice never duplicates a title.
List<MediaItem> buildPublicDomainItems() => [
  for (final title in publicDomainTitles)
    MediaItem(
      id: title.id,
      sourceId: publicDomainSourceId,
      kind: MediaKind.movie,
      title: title.title,
      year: title.year,
      locator: title.streamUrl,
      posterUrl: title.posterUrl,
      overview: '${title.overview}\n\n${title.licence} · ${title.credit}',
      genres: title.genres,
      quality: title.quality,
      container: 'MP4',
      addedAt: DateTime(2026, 11, 14),
    ),
];
