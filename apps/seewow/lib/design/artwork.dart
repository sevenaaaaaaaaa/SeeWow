import 'dart:io';

import 'package:flutter/material.dart';

/// One image widget for every artwork surface: local file, file:// URI or
/// authenticated remote URL. Keeps WebDAV/Emby posters working without each
/// screen re-implementing the branch.
class WowArt extends StatelessWidget {
  const WowArt({
    super.key,
    required this.url,
    this.headers = const {},
    this.fit = BoxFit.cover,
    this.fallback,
  });

  final String? url;
  final Map<String, String> headers;
  final BoxFit fit;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final u = url;
    final placeholder = fallback ?? const SizedBox.shrink();
    if (u == null || u.isEmpty || u.startsWith('seewow:')) return placeholder;
    if (u.startsWith('file://')) {
      final path = Uri.tryParse(u)?.toFilePath();
      if (path == null) return placeholder;
      return Image.file(File(path), fit: fit, errorBuilder: (_, __, ___) => placeholder);
    }
    if (u.startsWith('/')) {
      return Image.file(File(u), fit: fit, errorBuilder: (_, __, ___) => placeholder);
    }
    return Image.network(
      u,
      fit: fit,
      headers: headers.isEmpty ? null : headers,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
