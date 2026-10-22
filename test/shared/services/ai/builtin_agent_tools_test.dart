// 职责: 测试内置 Agent 工具白名单，确保 special-mode agent 与 subagent 工具权限正确。
// 关联文件:
//   lib/shared/services/ai/builtin_agent_tools.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/ai/builtin_agent_tools.dart';

void main() {
  group('builtinPrimaryAgentToolNames', () {
    test('special-mode primary agent 都允许 AgentSkill 工具', () {
      for (final slug in builtinPrimaryAgentSlugs) {
        final tools = builtinPrimaryAgentToolNames(slug);

        expect(
          tools,
          contains('AgentSkill'),
          reason: '$slug must be able to load bundled skills on demand',
        );
      }
    });

    test('special-mode primary agent 都允许 Run 工具', () {
      for (final slug in builtinPrimaryAgentSlugs) {
        final tools = builtinPrimaryAgentToolNames(slug);

        expect(tools, contains('Run'), reason: '$slug should have Run');
      }
    });

    test('已退役 chat primary agent 不再提供内置工具白名单', () {
      for (final slug in ['planner', 'writer', 'artist', 'chronicler']) {
        expect(
          builtinPrimaryAgentToolNames(slug),
          isNull,
          reason: '$slug was retired from chat primary agents',
        );
      }
    });
  });

  group('builtinSubAgentToolNames', () {
    test('所有内置 subagent 都允许 Run 工具', () {
      for (final slug in builtinSubAgentSlugs) {
        final tools = builtinSubAgentToolNames(slug);

        expect(tools, contains('Run'), reason: '$slug should have Run');
      }
    });

    test('writer subagent 可以创建、写入和删除资源', () {
      final tools = builtinSubAgentToolNames('writer');

      expect(tools, containsAll(['Create', 'Write', 'Edit', 'Remove']));
    });

    test('chronicler subagent 可以维护图谱关系', () {
      final tools = builtinSubAgentToolNames('chronicler');

      // 关系创建并入 Create /relations，不再有独立的 CreateRelation 授权。
      expect(tools, containsAll(['GraphSearch', 'Create', 'Remove']));
      expect(tools, isNot(contains('CreateRelation')));
      expect(tools, isNot(contains('SpawnAgent')));
    });

    test('explorer subagent 可以搜索图谱', () {
      final tools = builtinSubAgentToolNames('explorer');

      expect(tools, contains('GraphSearch'));
      expect(tools, isNot(contains('SpawnAgent')));
    });
  });
}
