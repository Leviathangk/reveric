// 职责: 表达 MCP 调用执行事实与内容交付完整性，避免业务字段覆盖宿主状态。
// 关联文件:
//   lib/shared/services/mcp/result_adapter.dart
//   lib/shared/services/mcp/tool_dispatcher.dart

import 'dart:convert';

enum McpExecutionState { not_started, succeeded, failed, unknown }

class McpCallResult {
  McpCallResult({
    required this.executionState,
    List<String> text = const [],
    this.structuredContent,
    this.contentComplete = true,
    List<Map<String, dynamic>> contentIssues = const [],
    this.errorCode,
    this.error,
    this.recovery,
    this.cancelled = false,
    this.rejected = false,
  }) : text = List.unmodifiable(text),
       contentIssues = List.unmodifiable(contentIssues) {
    if (executionState != McpExecutionState.succeeded &&
        (errorCode == null || error == null)) {
      throw ArgumentError('Unsuccessful MCP results require diagnostics');
    }
    if (executionState == McpExecutionState.unknown && contentComplete) {
      throw ArgumentError('Unknown execution cannot have complete content');
    }
  }
  final McpExecutionState executionState;
  final List<String> text;
  final Map<String, dynamic>? structuredContent;
  final bool contentComplete;
  final List<Map<String, dynamic>> contentIssues;
  final String? errorCode;
  final String? error;
  final String? recovery;
  final bool cancelled;
  final bool rejected;
  bool get ok => executionState == McpExecutionState.succeeded;
  Map<String, dynamic> toJson() => {
    'ok': ok,
    'executionState': executionState.name,
    'content': text.map((t) => {'type': 'text', 'text': t}).toList(),
    if (structuredContent != null) 'structuredContent': structuredContent,
    'contentComplete': contentComplete,
    'contentIssues': contentIssues,
    if (!ok) 'error_code': errorCode,
    if (!ok) 'error': error,
    if (recovery != null) 'recovery': recovery,
    if (cancelled) 'cancelled': true,
    if (rejected) 'rejected': true,
  };
  factory McpCallResult.fromJson(Map<String, dynamic> json) => McpCallResult(
    executionState: McpExecutionState.values.byName(
      json['executionState'] as String,
    ),
    text: (json['content'] as List)
        .map((item) => (item as Map)['text'] as String)
        .toList(),
    structuredContent: json['structuredContent'] as Map<String, dynamic>?,
    contentComplete: json['contentComplete'] as bool,
    contentIssues: (json['contentIssues'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(),
    errorCode: json['error_code'] as String?,
    error: json['error'] as String?,
    recovery: json['recovery'] as String?,
    cancelled: json['cancelled'] == true,
    rejected: json['rejected'] == true,
  );
  int get jsonBytes => utf8.encode(jsonEncode(toJson())).length;
}
