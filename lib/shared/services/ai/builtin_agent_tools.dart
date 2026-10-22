// 职责: 声明内置 Agent 的工具权限。
// 关联文件:
//   lib/shared/services/initialization/agent_seeds.dart
//   lib/shared/services/initialization/primary_agent_seeds.dart
//   lib/shared/services/initialization/subagent_seeds.dart
//   lib/desktop/widgets/ai/chat/panel.dart
//   lib/shared/agent/agent.dart

/// 用户可见 special-mode primary agent（Home → 提示词）。
/// Chat 主控已收敛为 runtime `orchestrator`，不再对应 AgentProfile。
const builtinPrimaryAgentSlugs = {
  'monologue_narrator',
  'roleplay_master',
  'theater_actor',
};

/// Chat SubAgent 白名单。`chronicler` 为 orchestrator 内部调用，不出现在管理 UI。
const builtinSubAgentSlugs = {
  'explorer',
  'writer',
  'chronicler',
  'review',
  'style_polish',
  'plot_architect',
  'character_analyst',
  'world_builder',
  'pacing_expert',
  'conflict_designer',
  'theme_guardian',
};

const builtinReadOnlyAgentToolNames = [
  'Read',
  'Glob',
  'Grep',
  'WebSearch',
  'WebFetch',
  'Run',
  'SpawnAgent',
  'TodoWrite',
  'AgentSkill',
];

const builtinWriterSubAgentToolNames = [
  'Read',
  'Glob',
  'Grep',
  'WebSearch',
  'WebFetch',
  'Create',
  'Write',
  'Edit',
  'Replace',
  'Remove',
  'Run',
  'TodoWrite',
  'AgentSkill',
];

const builtinExplorerSubAgentToolNames = [
  'Read',
  'Glob',
  'Grep',
  'WebSearch',
  'WebFetch',
  'GraphSearch',
  'Run',
  'AgentSkill',
];

const builtinChroniclerSubAgentToolNames = [
  'Read',
  'GraphSearch',
  // 关系创建并入 Create（`Create /relations`），不再需要单独的 CreateRelation。
  'Create',
  'Remove',
  'Write',
  'Edit',
  'Grep',
  'Run',
  'TodoWrite',
  'AgentSkill',
];

const builtinDefaultSubAgentToolNames = [
  'Read',
  'Glob',
  'Grep',
  'WebSearch',
  'WebFetch',
  'Create',
  'Write',
  'Edit',
  'Replace',
  'Run',
  'TodoWrite',
  'AgentSkill',
];

List<String>? builtinPrimaryAgentToolNames(String slug) {
  final names = switch (slug) {
    'monologue_narrator' ||
    'roleplay_master' ||
    'theater_actor' => builtinReadOnlyAgentToolNames,
    _ => null,
  };
  return names == null ? null : List<String>.from(names);
}

List<String>? builtinSubAgentToolNames(String slug) {
  if (!builtinSubAgentSlugs.contains(slug)) {
    return null;
  }
  if (slug == 'explorer') {
    return List<String>.from(builtinExplorerSubAgentToolNames);
  }
  if (slug == 'chronicler') {
    return List<String>.from(builtinChroniclerSubAgentToolNames);
  }
  if (slug == 'writer') {
    return List<String>.from(builtinWriterSubAgentToolNames);
  }
  return List<String>.from(builtinDefaultSubAgentToolNames);
}
