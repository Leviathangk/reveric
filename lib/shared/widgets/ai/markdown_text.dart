// 职责: AI 输出的 Markdown 正文 — GptMarkdown 渲染，流式生成时关闭选区，全角数字归一化；chat 与议会等 AI 模式共用。
// 关联文件:
//   lib/shared/widgets/stable_selection_area.dart
//   lib/shared/widgets/ai/chat/chat_message_parts.dart
//   lib/shared/widgets/ai/council/message_card.dart
//   lib/shared/widgets/ai/council/summary_card.dart
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../stable_selection_area.dart';
import 'markdown_code_block.dart';

/// 把全角数字（U+FF10–FF19）归一化为半角，避免 Markdown 渲染时数字占满 CJK 字宽、
/// 看起来过宽过散。只转换数字，刻意保留中文全角标点（「」，。！？（）等正常排版）。
String _normalizeFullwidthDigits(String input) {
  return input.replaceAllMapped(
    RegExp(r'[０-９]'),
    (m) => String.fromCharCode(m.group(0)!.codeUnitAt(0) - 0xFF10 + 0x30),
  );
}

class AiMarkdownText extends StatelessWidget {
  const AiMarkdownText(
    this.content, {
    super.key,
    required this.style,
    this.selectable = true,
    this.maxLines,
    this.overflow,
  });

  final String content;
  final TextStyle style;

  /// false 时内容不可选中：内容仍在流式增长，框架选区索引会失稳崩溃。
  final bool selectable;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    return StableSelectionArea(
      selectable: selectable,
      child: GptMarkdown(
        _normalizeFullwidthDigits(content.trim()),
        textDirection: Directionality.of(context),
        style: style,
        maxLines: maxLines,
        overflow: overflow,
        codeBuilder: buildMarkdownCodeBlock,
      ),
    );
  }
}
