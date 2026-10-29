// 职责: 对工具名称、用途和参数字段做确定性的中英文相关性排序。
// 关联文件:
//   lib/shared/services/ai/tool_catalog.dart

int toolSearchScore(
  String query, {
  required String name,
  required String description,
  required String fields,
}) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) {
    throw ArgumentError('Search query must not be empty');
  }
  final tokens = <String>{...normalized.split(RegExp(r'\s+'))};
  for (final match in RegExp(r'[\u3400-\u9fff]+').allMatches(normalized)) {
    final text = match.group(0)!;
    for (var i = 0; i < text.length - 1; i++) {
      tokens.add(text.substring(i, i + 2));
    }
  }
  var score = 0;
  for (final token in tokens) {
    if (name.toLowerCase().contains(token)) {
      score += 8;
    }
    if (description.toLowerCase().contains(token)) {
      score += 4;
    }
    if (fields.toLowerCase().contains(token)) {
      score += 1;
    }
  }
  return score;
}
