// 职责: 验证稳定 MCP 名称、部分目录、中文用途检索和摘要隔离。
// 关联文件:
//   lib/shared/services/ai/tool_catalog.dart
//   lib/shared/models/mcp/tool_descriptor.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/mcp/config.dart';
import 'package:reveric/shared/models/mcp/tool_descriptor.dart';
import 'package:reveric/shared/services/ai/tool_catalog.dart';
import 'package:reveric/shared/services/mcp/runtime.dart';
import 'runtime_test.dart' show FakeConnection;

void main() {
  test(
    'verified descriptions survive disconnect and foreground transitions',
    () async {
      final connections = <FakeConnection>[];
      final runtime = McpRuntime(
        connect: (_) async {
          final connection = FakeConnection();
          connections.add(connection);
          return connection;
        },
      );
      addTearDown(runtime.close);
      final config = McpServerConfig(
        name: 'notes',
        enabled: true,
        connection: McpHttpConfig(url: 'https://example.test'),
      );
      await runtime.configure(McpSettings([config]));
      await runtime.ensureReady('notes');
      final catalog = AgentToolCatalog(runtime: runtime, builtins: () => []);
      final prompt = catalog.summaryPrompt();
      connections.last.onClosed?.call();
      expect(catalog.summaryPrompt(), prompt);
      await runtime.ensureReady('notes');
      expect(catalog.summaryPrompt(), prompt);
      await runtime.suspend();
      expect(catalog.summaryPrompt(), prompt);
      await runtime.resume();
      expect(catalog.summaryPrompt(), prompt);
      await runtime.ensureReady('notes');
      expect(catalog.summaryPrompt(), prompt);
      await runtime.configure(
        McpSettings([
          config.copyWith(connection: McpHttpConfig(url: 'https://new.test')),
        ]),
      );
      expect(catalog.summaryPrompt(), isNot(prompt));
    },
  );
  test('names are sanitized and only hashed when too long', () {
    final valid = RegExp(r'^[a-zA-Z0-9_]+$');
    expect(mcpToolName('notes', 'search'), 'mcp__notes__search');
    expect(mcpToolName('my-notes', 'get-issue'), 'mcp__my_notes__get_issue');
    final long = mcpToolName('a' * 100, 'b' * 100);
    expect(long.length, 64);
    expect(valid.hasMatch(long), true);
    expect(valid.hasMatch(mcpToolName('资料', '搜索')), true);
  });
  test('tools whose sanitized names collide all get distinct hashes', () async {
    final tools = {
      'notes': ['a-b', 'a_b', 'search'],
      'a': ['b__c'],
      'a__b': ['c'],
    };
    final runtime = McpRuntime(
      connect: (config) async => _ToolsConnection(tools[config.name]!),
    );
    addTearDown(runtime.close);
    await runtime.configure(
      McpSettings([
        for (final name in tools.keys)
          McpServerConfig(
            name: name,
            enabled: true,
            connection: McpHttpConfig(url: 'https://example.test/$name'),
          ),
      ]),
    );
    await runtime.startEnabled();
    final names = runtime.tools.keys.toSet();
    expect(names, hasLength(5));
    expect(names, contains('mcp__notes__search'));
    expect(names, isNot(contains('mcp__notes__a_b')));
    expect(names, isNot(contains('mcp__a__b__c')));
    expect(names.where((n) => n.startsWith('mcp__notes__a_b_')), hasLength(2));
    expect(names.where((n) => n.startsWith('mcp__a__b__c_')), hasLength(2));
    for (final entry in runtime.tools.entries) {
      expect(entry.value.name, entry.key);
    }
  });
  test(
    'partial directory is explicit and only configured summaries enter prompt',
    () async {
      final runtime = McpRuntime(connect: (_) async => FakeConnection());
      addTearDown(runtime.close);
      await runtime.configure(
        McpSettings([
          McpServerConfig(
            name: 'notes',
            enabled: true,
            description: '搜索笔记',
            connection: McpHttpConfig(
              url: 'https://example.test',
              bearerToken: 'private-token',
            ),
          ),
          McpServerConfig(
            name: 'slow',
            enabled: true,
            connection: McpHttpConfig(url: 'https://example.test'),
          ),
        ]),
      );
      await runtime.ensureReady('notes');
      final catalog = AgentToolCatalog(runtime: runtime, builtins: () => []);
      final before = catalog.summaryPrompt();
      final found = await catalog.searchTool('笔记');
      expect(found['complete'], false);
      expect((found['tools'] as List).single['name'], 'mcp__notes__search');
      expect(found['pendingServers'], [
        {'name': 'slow', 'status': 'disconnected'},
      ]);
      expect(catalog.summaryPrompt(), before);
      expect(before, isNot(contains('private-token')));
      expect(before, isNot(contains('https://')));
      await expectLater(catalog.listTools(mcpServer: ''), throwsArgumentError);
      await expectLater(
        catalog.searchTool('notes', source: 'builtin', mcpServer: 'notes'),
        throwsArgumentError,
      );
    },
  );
}

class _ToolsConnection extends FakeConnection {
  _ToolsConnection(this.names);
  final List<String> names;
  @override
  Future<List<Map<String, dynamic>>> listTools() async => [
    for (final name in names)
      {
        'name': name,
        'inputSchema': {'type': 'object'},
      },
  ];
}
