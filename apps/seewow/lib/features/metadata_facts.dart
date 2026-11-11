import 'package:flutter/material.dart';

import '../domain/media_metadata.dart';
import 'metadata_languages_view.dart';

class MetadataFacts extends StatelessWidget {
  const MetadataFacts({
    super.key,
    required this.metadata,
    this.compact = false,
  });
  final MediaMetadata metadata;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final m = metadata;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (m.originalTitle.isNotEmpty) Text('原名：${m.originalTitle}'),
        if (m.language.isNotEmpty ||
            m.originalLanguage.isNotEmpty ||
            m.countries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              [
                if (m.language.isNotEmpty) '资料语言 ${m.language}',
                if (m.originalLanguage.isNotEmpty) '原始语言 ${m.originalLanguage}',
                if (m.countries.isNotEmpty) '地区 ${m.countries.join(' / ')}',
              ].join(' · '),
            ),
          ),
        MetadataLanguagesView(metadata: m, compact: compact),
        if (m.ratings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final rating in m.ratings)
                  Chip(
                    label: Text(
                      '${rating.source} ${rating.value.toStringAsFixed(1)}/${rating.scale.toStringAsFixed(rating.scale == rating.scale.roundToDouble() ? 0 : 1)}${rating.votes == null ? '' : ' · ${rating.votes} 票'}',
                    ),
                  ),
              ],
            ),
          ),
        if (m.people.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('演职人员 · ${m.people.length}'),
              initiallyExpanded: !compact,
              children: [
                for (final person in m.people.take(
                  compact ? 12 : m.people.length,
                ))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(person.name),
                    subtitle: Text(
                      [
                        person.role,
                        person.department,
                      ].where((s) => s.isNotEmpty).join(' · '),
                    ),
                  ),
                if (compact && m.people.length > 12)
                  Text('另有 ${m.people.length - 12} 位人员，确认后可在详情查看'),
              ],
            ),
          ),
        for (final note in m.notes)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(note, style: Theme.of(context).textTheme.bodySmall),
          ),
        if (m.provider.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '资料来源：${m.provider}${m.reviewed ? ' · 已确认' : ' · 随来源刷新'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
