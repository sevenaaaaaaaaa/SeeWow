import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/library_store.dart';
import '../domain/media_item.dart';
import '../domain/media_metadata.dart';
import '../metadata/nfo_reader.dart';

Future<void> editMetadata(
  BuildContext context,
  LibraryStore store,
  MediaItem item,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _Editor(store: store, item: item),
);

class _Editor extends StatefulWidget {
  const _Editor({required this.store, required this.item});
  final LibraryStore store;
  final MediaItem item;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final _form = GlobalKey<FormState>();
  final _fields = <String, TextEditingController>{};
  bool _busy = false;
  String? _error;
  MediaMetadata? _basis;
  TextEditingController field(String name) =>
      _fields.putIfAbsent(name, TextEditingController.new);
  @override
  void initState() {
    super.initState();
    _fill(
      widget.item.metadata ??
          MediaMetadata(
            id: 0,
            mediaType: widget.item.kind.name,
            title: widget.item.title,
            year: widget.item.year,
            overview: widget.item.overview,
            genres: widget.item.genres,
          ),
    );
    field('title').text = widget.item.title;
    field('poster').text = widget.item.posterUrl ?? '';
    field('backdrop').text = widget.item.backdropUrl ?? '';
  }

  void _fill(MediaMetadata m) {
    _basis = m;
    final values = {
      'title': m.title,
      'original': m.originalTitle,
      'year': m.year?.toString() ?? '',
      'overview': m.overview,
      'genres': m.genres.join(', '),
      'language': m.originalLanguage,
      'countries': m.countries.join(', '),
      'poster': m.posterUrl ?? '',
      'backdrop': m.backdropUrl ?? '',
      'people': m.people
          .map((p) => '${p.name}|${p.role}|${p.department}')
          .join('\n'),
      'ratings': m.ratings
          .map((r) => '${r.source}|${r.value}|${r.scale}|${r.votes ?? ''}')
          .join('\n'),
    };
    for (final entry in values.entries) {
      field(entry.key).text = entry.value;
    }
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> split(String key) =>
      field(key).text
          .split(RegExp(r'[,，]'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['nfo'],
      );
      if (file == null || !mounted) return;
      if ((await file.length() ?? 2097153) > 2 * 1024 * 1024)
        throw const FormatException('NFO 文件不能超过 2 MiB');
      final data = NfoInfo.parse(
        NfoInfo.decode(await file.readAsBytes()),
        directory: file.path == null ? null : File(file.path!).parent.uri,
      );
      if (!mounted) return;
      setState(() {
        _fill(
          data.asMetadata(
            fallbackTitle: widget.item.title,
            mediaType: widget.item.kind.name,
          ),
        );
      });
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : '无法读取 NFO 文件',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final people = <MediaPerson>[];
      for (final line
          in const LineSplitter()
              .convert(field('people').text)
              .where((s) => s.trim().isNotEmpty)) {
        final parts = line.split('|').map((s) => s.trim()).toList();
        if (parts.first.isEmpty || parts.length > 3)
          throw const FormatException('人员格式：姓名|角色|部门，每人一行');
        people.add(
          MediaPerson(
            name: parts.first,
            role: parts.length > 1 ? parts[1] : '',
            department: parts.length > 2 ? parts[2] : 'Cast',
          ),
        );
      }
      final ratings = <MediaRating>[];
      for (final line
          in const LineSplitter()
              .convert(field('ratings').text)
              .where((s) => s.trim().isNotEmpty)) {
        final p = line.split('|').map((s) => s.trim()).toList();
        if (p.length < 2 ||
            p.length > 4 ||
            p.first.isEmpty ||
            double.tryParse(p[1]) == null)
          throw const FormatException('评分格式：来源|分数|满分|票数，每项一行');
        final r = MediaRating(
          source: p.first,
          value: double.parse(p[1]),
          scale: p.length > 2 ? double.tryParse(p[2]) ?? 0 : 10,
          votes: p.length > 3 && p[3].isNotEmpty ? int.tryParse(p[3]) : null,
        );
        if (!r.valid) throw const FormatException('评分应在 0 到满分之间');
        ratings.add(r);
      }
      final match = MediaMetadata.fromJson({
        ...?_basis?.toJson(),
        'id': 0,
        'provider': 'local',
        'reviewed': true,
        'mediaType': widget.item.kind == MediaKind.episode
            ? 'episode'
            : widget.item.kind.name,
        'title': field('title').text.trim(),
        'originalTitle': field('original').text.trim(),
        'year': int.tryParse(field('year').text.trim()),
        'overview': field('overview').text.trim(),
        'genres': split('genres'),
        'originalLanguage': field('language').text.trim(),
        'countries': split('countries'),
        'posterUrl': field('poster').text.trim().isEmpty
            ? null
            : field('poster').text.trim(),
        'backdropUrl': field('backdrop').text.trim().isEmpty
            ? null
            : field('backdrop').text.trim(),
        'replaceArtwork': true,
        'people': people.map((p) => p.toJson()).toList(),
        'ratings': ratings.map((r) => r.toJson()).toList(),
        'rating': ratings.isEmpty
            ? widget.item.rating
            : ratings.first.value / ratings.first.scale * 10,
      });
      await widget.store.applyMetadata(widget.item.id, match);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is FormatException
              ? e.message.toString()
              : '保存失败，请稍后重试',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('编辑媒体资料'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('适用于课程、家庭影像、演唱会、音乐等内容。只修改本机资料，分集只修改当前集。'),
                TextButton.icon(
                  onPressed: _busy ? null : _import,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('从 NFO 读取资料'),
                ),
                for (final entry in {
                  'title': '标题',
                  'original': '原始标题',
                  'year': '年份',
                  'overview': '简介',
                  'genres': '类型（逗号分隔）',
                  'language': '原始语言',
                  'countries': '国家／地区（逗号分隔）',
                  'people': '人员：姓名|角色|部门（每人一行）',
                  'ratings': '评分：来源|分数|满分|票数（每项一行）',
                  'poster': '封面地址或本机路径',
                  'backdrop': '背景图地址或本机路径',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextFormField(
                      controller: field(entry.key),
                      enabled: !_busy,
                      minLines:
                          ['overview', 'people', 'ratings'].contains(entry.key)
                          ? 2
                          : 1,
                      maxLines:
                          ['overview', 'people', 'ratings'].contains(entry.key)
                          ? 5
                          : 1,
                      decoration: InputDecoration(labelText: entry.value),
                      validator: (v) {
                        final text = v?.trim() ?? '';
                        if (entry.key == 'title' && text.isEmpty)
                          return '请填写标题';
                        if (entry.key == 'year' &&
                            text.isNotEmpty &&
                            (int.tryParse(text) == null ||
                                int.parse(text) < 1 ||
                                int.parse(text) > 9999))
                          return '年份需要为 1 到 9999';
                        if (['poster', 'backdrop'].contains(entry.key) &&
                            text.isNotEmpty) {
                          final u = Uri.tryParse(text);
                          if (u == null ||
                              u.userInfo.isNotEmpty ||
                              (!['http', 'https'].contains(u.scheme) &&
                                  !File(text).isAbsolute))
                            return '使用 HTTP(S) 地址或本机绝对路径';
                        }
                        return null;
                      },
                    ),
                  ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('保存媒体资料'),
        ),
      ],
    ),
  );
}
