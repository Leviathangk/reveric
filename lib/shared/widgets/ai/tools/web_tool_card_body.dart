// 职责: Web 工具摘要卡片体 — 展示查询或 URL，以及网页命中摘要。
// 关联文件:
//   lib/shared/widgets/ai/tools/tool_card_common.dart
//   lib/shared/models/ai_message_block.dart
//   lib/shared/localization/locale_keys.dart
import 'package:flutter/material.dart';

import 'package:reveric/shared/localization/app_localization.dart';
import 'package:reveric/shared/localization/locale_keys.dart';
import 'package:reveric/shared/models/ai_message_block.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'tool_card_common.dart';

class WebToolCardBody extends StatelessWidget {
  const WebToolCardBody({super.key, required this.block});

  final AiToolCallBlock block;

  @override
  Widget build(BuildContext context) {
    final preview = _buildPreview();
    final chips = <String>[
      if (block.toolName == 'WebSearch')
        (block.arguments['query'] as String? ?? '').trim(),
      if (block.toolName == 'WebFetch')
        (block.arguments['url'] as String? ?? '').trim(),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AiToolInfoChips(items: chips),
        if (preview != null) ...[
          const SizedBox(height: RevericSpacing.sm),
          AiToolPreviewBlock(
            label: context.t(LocaleKeys.aiToolPreview),
            text: preview,
            maxLines: 8,
          ),
        ],
      ],
    );
  }

  String? _buildPreview() {
    if (block.toolName == 'WebSearch') {
      final items = (block.result?['results'] as List?)
          ?.whereType<Map>()
          .toList();
      if (items == null || items.isEmpty) {
        return null;
      }
      return items
          .take(4)
          .map((item) {
            final map = Map<String, dynamic>.from(item);
            final title = (map['title'] ?? map['url'] ?? '').toString().trim();
            final snippet = (map['snippet'] ?? '').toString().trim();
            if (title.isEmpty) return '';
            return snippet.isEmpty ? title : '$title\n$snippet';
          })
          .where((line) => line.isNotEmpty)
          .join('\n\n');
    }
    final markdown = (block.result?['markdown'] as String?)?.trim();
    if (markdown != null && markdown.isNotEmpty) {
      return markdown;
    }
    final content = (block.result?['content'] as String?)?.trim();
    if (content != null && content.isNotEmpty) {
      return content;
    }
    return null;
  }
}
