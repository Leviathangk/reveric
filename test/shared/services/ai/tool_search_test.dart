// 职责: 运行固定中英文发现夹具，验证同名工具隔离和停用服务过滤。
// 关联文件:
//   lib/shared/services/ai/tool_catalog.dart
//   lib/shared/services/ai/tool_search.dart
//   test/fixtures/mcp/evaluation_cases.json
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/services/ai/tool_catalog.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import '../mcp/runtime_test.dart' show FakeConnection;

class SearchConnection extends FakeConnection {
  SearchConnection(this.field);
  final String field;
  @override
  Future<List<Map<String, dynamic>>> listTools() async => [
    {
      'name': 'search',
      'description': 'Search lookup',
      'inputSchema': {
        'type': 'object',
        'properties': {
          field: {'type': 'string'},
        },
      },
    },
  ];
}

void main() {
  test('MCP-E02/E03: twenty bilingual queries preserve tool identity', () async {
    final fixture =
        jsonDecode(
              await File(
                'test/fixtures/mcp/evaluation_cases.json',
              ).readAsString(),
            )
            as Map;
    final runtime = McpRuntime(
      connect: (config) async => SearchConnection(
        config.name == 'notes' ? 'documentId' : 'characterId',
      ),
    );
    addTearDown(runtime.close);
    final settings = McpSettings([
      McpServerConfig(
        name: 'notes',
        enabled: true,
        description:
            'Search notes, find documents and read note archive. 搜索笔记 查询资料 检索文档 读取笔记 查找资料',
        connection: McpHttpConfig(url: 'https://notes.example.test'),
      ),
      McpServerConfig(
        name: 'people',
        enabled: true,
        description:
            'Search characters, find people and person name cast lookup. 搜索角色 查询人物 查找角色 人物名字 角色设定',
        connection: McpHttpConfig(url: 'https://people.example.test'),
      ),
    ]);
    await runtime.configure(settings);
    await runtime.startEnabled();
    final catalog = AgentToolCatalog(runtime: runtime, builtins: () => []);
    for (final query in fixture['searchQueries'] as List) {
      final result = await catalog.searchTool(query['query'] as String);
      final names = (result['tools'] as List)
          .map((t) => (t as Map)['name'])
          .toList();
      expect(
        names.take(8),
        contains(query['expected']),
        reason: query['id'] as String,
      );
      expect(names.first, query['expected'], reason: query['id'] as String);
    }
    expect(
      runtime.tools.keys,
      containsAll(['mcp__notes__search', 'mcp__people__search']),
    );
    await runtime.configure(
      McpSettings([
        settings.servers.first.copyWith(enabled: false),
        settings.servers.last,
      ]),
    );
    expect((await catalog.searchTool('notes'))['tools'], isEmpty);
  });
}
