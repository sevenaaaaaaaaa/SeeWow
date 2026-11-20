import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../design/tokens.dart';
import '../sources/web_page_parse.dart';

/// 在隔离 WebView 里打开一个分享页，抓它自己请求的播放地址。
///
/// 只有在 [ParseComponent.runsHere] 为真的平台上才会被构造（iOS / Android）。
/// 页面脚本在这里执行，所以每次进来都先由调用方确认，且不共享应用凭据。
class WebParseScreen extends StatefulWidget {
  const WebParseScreen({
    super.key,
    required this.pageUrl,
    this.title = '网页解析',
    this.timeout = const Duration(seconds: 30),
  });

  final String pageUrl;
  final String title;
  final Duration timeout;

  @override
  State<WebParseScreen> createState() => _WebParseScreenState();
}

class _WebParseScreenState extends State<WebParseScreen> {
  late final WebViewController _controller;
  Timer? _poll;
  late DateTime _started;
  double _progress = 0;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _started = DateTime.now();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0B0B0D))
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            final url = change.url;
            if (url != null) _consider(url);
          },
          onProgress: (value) {
            if (mounted) setState(() => _progress = value / 100);
          },
          onWebResourceError: (_) {
            // 页面自己的资源失败很常见（广告、统计），不影响抓地址。
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.pageUrl));
    _poll = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _probe(),
    );
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _consider(String text) {
    if (_done) return;
    final direct = mediaUrlFrom(text);
    final inner = direct ?? mediaUrlFrom(unwrapUrlParam(text) ?? '');
    if (inner == null) {
      if (DateTime.now().difference(_started) > widget.timeout) {
        _fail('等了 ${widget.timeout.inSeconds} 秒没等到播放地址');
      }
      return;
    }
    _done = true;
    _poll?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop(inner);
  }

  Future<void> _probe() async {
    if (_done || !mounted) return;
    try {
      final raw = await _controller.runJavaScriptReturningResult(_probeScript);
      final text = raw.toString();
      _consider(text);
    } catch (_) {
      // 页面还没准备好时会抛，下一次再试。
    }
  }

  void _fail(String message) {
    if (_done) return;
    _done = true;
    _poll?.cancel();
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(widget.pageUrl);
    final elapsed = DateTime.now().difference(_started).inSeconds;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0D),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WowType.display(18, FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          uri?.host ?? widget.pageUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: WowType.monoLabel(
                            9,
                            color: Colors.white.withValues(alpha: 0.4),
                            spacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            if (_error == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _progress == 0 ? null : _progress,
                          minHeight: 3,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${elapsed}s',
                      style: WowType.monoLabel(
                        9,
                        color: Colors.white.withValues(alpha: 0.45),
                        spacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: WowType.body(
                                13,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              children: [
                                OutlinedButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('关闭'),
                                ),
                                FilledButton(
                                  onPressed: () {
                                    setState(() {
                                      _error = null;
                                      _done = false;
                                      _started = DateTime.now();
                                    });
                                    _controller.reload();
                                    _poll = Timer.periodic(
                                      const Duration(milliseconds: 700),
                                      (_) => _probe(),
                                    );
                                  },
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  : WebViewWidget(controller: _controller),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '这个页面在隔离 WebView 里运行，会执行它自己的脚本；本应用不向它提供任何账号。找到 m3u8 就会自动返回。',
                style: WowType.monoLabel(
                  8.5,
                  color: Colors.white.withValues(alpha: 0.3),
                  spacing: 0.6,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _probeScript = r'''
(function(){
  var out=[];
  try{
    document.querySelectorAll('video,audio').forEach(function(v){
      if(v.currentSrc)out.push(v.currentSrc);
      if(v.src)out.push(v.src);
      var s=v.querySelector&&v.querySelector('source');
      if(s&&s.src)out.push(s.src);
    });
  }catch(e){}
  try{
    performance.getEntriesByType('resource').forEach(function(e){
      if(/\.(m3u8|mp4|flv)/i.test(e.name))out.push(e.name);
    });
  }catch(e){}
  try{
    var h=document.documentElement.innerHTML;
    var m=h.match(/https?:[^\s"'\\]+?\.(m3u8|mp4|flv)[^\s"'\\]*/i);
    if(m)out.push(m[0]);
  }catch(e){}
  return out.join('\n');
})()
''';
}
