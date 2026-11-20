import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seewow/sources/tvbox_config.dart';

/// 样本取自真实配置：home.jundie.top:81/top98.json（俊于）与
/// raw.githubusercontent.com/qist/tvbox/master/jsm.json（电视自用），
/// 只保留每类站点各若干条，字节为原始内容。
String fixture(String name) =>
    File('test/fixtures/$name').readAsStringSync();

void main() {
  group('分类', () {
    test('jar / js / py / 苹果CMS 各自归位', () {
      expect(TvBoxConfig.classify('csp_SP360'), TvBoxSiteKind.jarSpider);
      expect(TvBoxConfig.classify('csp_Config'), TvBoxSiteKind.jarSpider);
      expect(
        TvBoxConfig.classify('./lib/drpy2.min.js'),
        TvBoxSiteKind.jsSpider,
      );
      expect(
        TvBoxConfig.classify('http://home.jundie.top:666/JS/drpy.min.js'),
        TvBoxSiteKind.jsSpider,
      );
      expect(TvBoxConfig.classify('./py/ITalkBBTV.py'), TvBoxSiteKind.pySpider);
      expect(
        TvBoxConfig.classify('https://cj.lziapi.com/api.php/provide/vod/'),
        TvBoxSiteKind.cms,
      );
      expect(
        TvBoxConfig.classify('https://suoniapi.com/api.php/provide/vod/at/xml/'),
        TvBoxSiteKind.cms,
      );
      expect(
        TvBoxConfig.classify('https://example.test/feed.json?a=1'),
        TvBoxSiteKind.directHttp,
      );
    });

    test('只有 http 采集站算可播', () {
      final report = TvBoxConfig.parse(
        fixture('tvbox_dianshi_subset.json'),
        baseUri: Uri.parse(
          'https://raw.githubusercontent.com/qist/tvbox/master/jsm.json',
        ),
      );
      expect(report.countOf(TvBoxSiteKind.cms), 3);
      expect(report.countOf(TvBoxSiteKind.jarSpider), 2);
      expect(report.countOf(TvBoxSiteKind.jsSpider), 1);
      expect(report.countOf(TvBoxSiteKind.pySpider), 1);
      expect(report.playableSites.length, 3);
      expect(report.blockedCount, 4);
      expect(report.spiderJar, isNull);
    });
  });

  group('直播源', () {
    test('直链直播源原样保留，proxy:// 解成真实地址', () {
      final report = TvBoxConfig.parse(
        fixture('tvbox_junyu_subset.json'),
        baseUri: Uri.parse('http://home.jundie.top:81/top98.json'),
      );
      expect(report.lives.length, 2);
      expect(
        report.lives.first.uri.toString(),
        'http://home.jundie.top:81/Cat/tv/live.txt',
      );
      expect(report.lives.first.epgUrl, contains('epg.51zmt.top'));
      final proxy = report.lives.last;
      expect(proxy.viaProxy, isTrue);
      expect(proxy.uri.toString(), 'http://home.jundie.top:81/Cat/tv/live.txt');
      expect(report.notes, contains('已把 proxy:// 直播源解成直链'));
    });

    test('proxy:// 的 ext 解不出来时跳过并说明', () {
      const config = '{"lives":[{"name":"坏源","url":"proxy://do=live&ext=!!!"}]}';
      final report = TvBoxConfig.parse(
        config,
        baseUri: Uri.parse('https://example.test/config.json'),
      );
      expect(report.lives, isEmpty);
      expect(report.warnings.any((line) => line.contains('proxy://')), isTrue);
    });
  });

  group('拒绝执行', () {
    test('爬虫站点进警告，不进可播列表', () {
      final report = TvBoxConfig.parse(
        fixture('tvbox_dianshi_subset.json'),
        baseUri: Uri.parse('https://example.test/config.json'),
      );
      expect(
        report.warnings.any((line) => line.contains('jar 爬虫')),
        isTrue,
      );
      expect(
        report.warnings.any((line) => line.contains('JS 爬虫')),
        isTrue,
      );
      expect(
        report.warnings.any((line) => line.contains('Python 爬虫')),
        isTrue,
      );
      expect(
        report.warnings.any((line) => line.contains('外挂解析')),
        isTrue,
      );
      expect(report.playableSites.every((site) => !site.api!.startsWith('csp_')), isTrue);
    });

    test('网页或空内容直接报错，不猜', () {
      expect(
        () => TvBoxConfig.parse('<html></html>', baseUri: Uri.parse('https://a.test/x')),
        throwsFormatException,
      );
      expect(
        () => TvBoxConfig.parse('', baseUri: Uri.parse('https://a.test/x')),
        throwsFormatException,
      );
    });

    test('相对路径按配置地址解析', () {
      final report = TvBoxConfig.parse(
        jsonEncode({
          'lives': [
            {'name': '本机列表', 'url': './tvboxtv.txt'},
          ],
        }),
        baseUri: Uri.parse('https://example.test/dir/config.json'),
      );
      expect(report.lives.single.uri.toString(), 'https://example.test/dir/tvboxtv.txt');
    });
  });
}
