// 职责: ToolDef → JSON Schema 转换 — provider client 工具格式适配
// 关联文件:
//   lib/shared/agent/agent_tool_dispatcher.dart
//   lib/shared/agent/client/openai_client.dart
//   lib/shared/agent/client/anthropic_client.dart
//   lib/shared/agent/client/gemini_client.dart

import '../agent_tool_dispatcher.dart' show ToolDef;

Map<String, dynamic> toolDefToJsonSchema(ToolDef tool) {
  return {
    'type': 'object',
    'properties': {
      for (final entry
          in (tool.inputSchema['properties'] as Map<String, dynamic>?)
                  ?.entries ??
              <MapEntry<String, dynamic>>[])
        entry.key: entry.value,
    },
    if (tool.inputSchema['required'] case final List<dynamic> required_)
      'required': required_,
    'additionalProperties': ?tool.inputSchema['additionalProperties'],
  };
}
