import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/domain/media_item.dart';
import 'package:seewow/domain/online_source.dart';
import 'package:seewow/features/work_detail_view.dart';
import 'package:seewow/sources/cms_vod_client.dart';
import 'package:seewow/sources/online_vod_service.dart';
import 'package:seewow/sources/work_aggregator.dart';

OnlineSite _site(String id) =>
    OnlineSite(id: id, name: '$id站', api: 'https://$id.test/api.php/provide/vod');

CmsVodItem _item(String name, {bool direct = true}) => CmsVodItem(
  id: name,
  name: name,
  year: '2024',
  remarks: direct ? 'HD1080P' : '更新至2集',
  playFrom: 'lzm3u8',
  playUrl: '第01集\$${direct ? 'https://cdn.test/1.m3u8' : 'https://site.test/play/1'}',
);

void main() {
  testWidgets('作品详情：先说能不能看，再给源矩阵，点「开始看」直接起播', (tester) async {
    final work = WorkAggregator().group([
      OnlineSearchHit(_site('a'), _item('某片', direct: false)),
      OnlineSearchHit(_site('b'), _item('某片')),
    ]).single;

    MediaItem? played;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkDetailView(work: work, onPlay: (item) => played = item),
        ),
      ),
    );
    await tester.pump();

    // 一行决断 + 两个源都写清了。
    expect(find.text('某片'), findsOneWidget);
    expect(find.textContaining('可直连'), findsWidgets);
    expect(find.textContaining('b站'), findsWidgets);
    expect(find.textContaining('需解析'), findsWidgets);
    expect(find.text('开始看'), findsOneWidget);

    await tester.tap(find.text('开始看'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(played, isNotNull, reason: '点一次就该起播，不用再选源');
    expect(played!.locator, contains('.m3u8'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('没有源时给出明确结论，不显示一个坏按钮', (tester) async {
    const work = Work(
      id: 'x',
      title: '没有源的作品',
      year: 2024,
      posterUrl: null,
      rating: null,
      overview: '',
      sources: [],
      localEpisodes: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorkDetailView(work: work, onPlay: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('这部作品暂时没有可用源'), findsOneWidget);
    // 没有源时主按钮必须是禁用的，不能点下去什么都不发生。
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
