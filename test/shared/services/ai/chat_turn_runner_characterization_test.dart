// 职责: 验证聊天执行、技能作用域及子任务完成通知的模型输入、持久化和写入归属。
// 关联文件:
//   lib/shared/services/ai/chat_turn_runner.dart
//   lib/shared/services/ai/chat.dart
//   lib/shared/services/ai/tools.dart
//   lib/shared/agent/fake_agent.dart
//   lib/shared/agent/agent_context_manager.dart
//   lib/shared/providers/ai_providers.dart
//   lib/shared/models/queued_chat_message.dart
//   lib/shared/providers/novel_agent_skill_providers.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/providers/settings_providers.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hooks_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:reveric/shared/agent/agent.dart';
import 'package:reveric/shared/agent/agent_config.dart';
import 'package:reveric/shared/agent/agent_context_manager.dart';
import 'package:reveric/shared/agent/agent_hook.dart';
import 'package:reveric/shared/agent/client.dart';
import 'package:reveric/shared/agent/client/provider_history_preflight.dart';
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/agent/message.dart';
import 'package:reveric/shared/database/app_database.dart' hide AiChatSession;
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/content_kind.dart';
import 'package:reveric/shared/models/novel_agent_skill.dart';
import 'package:reveric/shared/models/queued_chat_message.dart';
import 'package:reveric/shared/models/subagent.dart';
import 'package:reveric/shared/providers/ai_providers.dart';
import 'package:reveric/shared/providers/novel_agent_skill_providers.dart';
import 'package:reveric/shared/providers/novel_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/subagent_providers.dart';
import 'package:reveric/shared/providers/spawn_agent_run_providers.dart';
import 'package:reveric/shared/services/ai/chat.dart';
import 'package:reveric/shared/services/ai/agent_message_mapping.dart';
import 'package:reveric/shared/services/ai/chat_turn_outcome.dart';
import 'package:reveric/shared/services/ai/chat_turn_runner.dart';
import 'package:reveric/shared/widgets/ai/chat/ui_message.dart';
import 'package:reveric/shared/services/ai/prompts/ai_prompt_service.dart';
import 'package:reveric/shared/services/ai/session_persistence.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

import '../../../helpers/spawn_agent_runtime_fixture.dart';

/// 一段 chatStream 脚本：先 yield [events]，若 [error] 非 null 则在最后抛出。
class _StreamScript {
  const _StreamScript({this.events = const [], this.error});
  final List<StreamEvent> events;
  final Object? error;
}

/// 按 [_StreamScript] 列表顺序消费的 ProviderClient。
/// 每次 chatStream 取下一段脚本；模拟中途断连。
class _FlakyStreamClient implements ProviderClient {
  _FlakyStreamClient(this.scripts);
  final List<_StreamScript> scripts;
  int calls = 0;
  final List<List<AgentMessage>> capturedMessages = [];

  @override
  Stream<StreamEvent> chatStream({
    required List<AgentMessage> messages,
    List<ToolDef>? tools,
    AgentConfig? options,
  }) async* {
    capturedMessages.add(List<AgentMessage>.from(messages));
    final script = scripts[calls];
    calls += 1;
    for (final event in script.events) {
      yield event;
    }
    final error = script.error;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<ChatResponse> chat({
    required List<AgentMessage> messages,
    List<ToolDef>? tools,
    AgentConfig? options,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<List<double>> embed(String text, {String? model}) async => const [];

  @override
  void cancel() {}
}

/// 记录每次 executeTool 时 `context.sourceTurnId` 的值（值拷贝，因 context 可变）。
/// [onTool] 用于在某个工具执行期间注入副作用（模拟工具运行时的「立即发送」）。
class _TurnIdCapturingDispatcher implements AgentToolDispatcher {
  _TurnIdCapturingDispatcher({this.onTool});

  final Future<void> Function(String toolName)? onTool;
  final capturedTurnIds = <String, String?>{};

  static const _defs = [
    ToolDef(name: 'T1', description: 't1', inputSchema: {'type': 'object'}),
    ToolDef(name: 'T2', description: 't2', inputSchema: {'type': 'object'}),
  ];

  @override
  Future<Map<String, dynamic>> executeTool({
    required String name,
    required Map<String, dynamic> input,
    String? callId,
    bool emitEvents = true,
    ToolExecutionContext? context,
  }) async {
    capturedTurnIds[name] = context?.sourceTurnId;
    if (onTool != null) {
      await onTool!(name);
    }
    return {'ok': true};
  }

  @override
  List<String> allToolNames() => _defs.map((d) => d.name).toList();

  @override
  List<ToolDef> allToolDefs() => _defs;

  @override
  List<ToolDef> toolDefsForNames(List<String> names) =>
      _defs.where((def) => names.contains(def.name)).toList();
}

/// 测试用 DeviceIdService 替身 — 避免触达 SharedPreferences / path_provider。

/// 暴露可控 toolManager / providerClient / agentConfig 的 AiClient 测试替身。
/// 用于 runSlashCommand 路径：runner 会读取 aiService.toolManager 并写入 skillLoader。
class _ScopedSkillAiClient extends AiClient {
  _ScopedSkillAiClient({
    required this.toolManager,
    required this.providerClient,
  }) : super(aiProviderBuiltinDefaults.first, chatModel: 'test-model');

  @override
  final AiToolManager? toolManager;

  @override
  final ProviderClient providerClient;

  @override
  AgentConfig get agentConfig => const AgentConfig();
}

class _DelayedGlobalSubAgents extends GlobalSubAgents {
  static late Completer<List<SubAgent>> pending;

  @override
  Future<List<SubAgent>> build() => pending.future;
}

class _CompletionPersistence extends AiSessionPersistenceService {
  _CompletionPersistence(super.database, super.novelId);
  bool fail = false;
  Future<void> Function()? beforeSave;

  @override
  Future<void> upsertCompletedMessages({
    required String sessionId,
    required List<AiMessage> messages,
    required NovelContentDatabase novelDatabase,
    AgentContextSnapshot? contextSnapshot,
  }) async {
    await beforeSave?.call();
    if (fail) {
      throw StateError('injected notification persistence failure');
    }
    await super.upsertCompletedMessages(
      sessionId: sessionId,
      messages: messages,
      novelDatabase: novelDatabase,
      contextSnapshot: contextSnapshot,
    );
  }
}

class _BeforeLLMCallback extends AgentHook {
  _BeforeLLMCallback(this.callback);

  final Future<void> Function() callback;

  @override
  Future<HookAction<BeforeLLMContext>> beforeLLM(BeforeLLMContext ctx) async {
    await callback();
    return const HookAction.proceed();
  }
}

const _chronicler = SubAgent(
  id: 'builtin-chronicler',
  slug: 'chronicler',
  name: '编年史者',
  description: '整理章节硬事实',
  prompt: '',
  scope: SubAgentScope.global,
  sortOrder: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // aiSettingsProvider 默认会触发 keepAlive 的 appSettingsDatabaseProvider，
  // 进而调用 AppDatabase() factory + path_provider，在非 widget 测试里抛
  // MissingPluginException(getTemporaryDirectory) 并污染后续测试。
  // 这里直接覆盖为 AiSettings.defaults()，断开 DB 链路。
  ProviderContainer buildTestContainer({List<Override> overrides = const []}) {
    return ProviderContainer(
      overrides: [
        aiSettingsProvider.overrideWithValue(AiSettings.defaults()),
        ...overrides,
      ],
    );
  }

  /// 构造一个真实但无副作用的 AiToolManager（in-memory DB + 关闭回调）。
  /// runSlashCommand 仅写入 toolManager.skillLoader，不会触发工具分发，
  /// 因此无需 registerAllTools，_resourceHandlers 也不会被求值。
  AiToolManager buildTestToolManager({
    AiAskUserCallback? askUserCallback,
    String workId = 'test_work',
    String contentKind = contentKindNovel,
  }) {
    final contentDb = NovelContentDatabase.forTest(NativeDatabase.memory());
    final appDb = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(() async {
      await contentDb.close();
      await appDb.close();
    });

    final actionsService = NovelActionsService(appDb);
    final contentService = NovelContentService(contentDb);
    final workingOverlay = WorkingOverlayService(
      contentDb,
      contentService,
      novelActionsService: actionsService,
    );
    return AiToolManager(
      contentService,
      workingOverlayService: workingOverlay,
      askUserCallback: askUserCallback,
      workId: workId,
      contentKind: contentKind,
    );
  }

  Novel testWork(String id, String kind) => Novel(
    id: id,
    title: 'Test work',
    authorName: '',
    description: '',
    status: 'draft',
    type: 'original',
    contentKind: kind,
    wordCount: 0,
    category: '',
    tags: const [],
    draft: false,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    deletedAt: notDeletedSentinel,
  );

  // 提供绑定作品快照；databasePath 留空，隔离与事件循环无关的持久化。
  // agent 直接注入 runtime，绕过 getOrCreateChatAgent 的真实构建。
  ChatTurnRunner buildRunner(
    ProviderContainer container, {
    String novelId = 'test_work',
    String? databasePath,
    String contentKind = contentKindNovel,
    Novel? novel,
    String? userRules,
    void Function(String message)? onComposerWarning,
    void Function(Agent agent)? onAgentContextCompacted,
    QueuedChatMessage? Function(String? sessionId)? takeQueuedMessage,
  }) {
    return ChatTurnRunner(
      container: container,
      novel: novel ?? testWork(novelId, contentKind),
      databasePath: databasePath,
      // runTurn 不调用 aiPromptService（仅被绕过的 getOrCreateChatAgent 用），任意实例即可。
      // runSlashCommand 调用 aiPromptService.agent.buildSubAgentPrompt — 同样无外部依赖。
      aiPromptService: AiPromptService(),
      promptContext: AiSessionContext(
        userRules: userRules,
        databasePath: databasePath,
        novelName: 'Test Novel',
        contentKind: contentKind,
      ),
      onComposerWarning: onComposerWarning,
      onAgentContextCompacted: onAgentContextCompacted,
      takeQueuedMessage: takeQueuedMessage,
    );
  }

  for (final workId in ['', ' \t\n ']) {
    test('rejects a blank work ID ${workId.codeUnits}', () {
      final container = buildTestContainer();
      addTearDown(container.dispose);
      expect(
        () => buildRunner(container, novelId: workId),
        throwsArgumentError,
      );
    });
  }

  test(
    'waits for global subagents before taking the first turn snapshot',
    () async {
      _DelayedGlobalSubAgents.pending = Completer<List<SubAgent>>();
      final container = buildTestContainer(
        overrides: [
          globalSubAgentsProvider.overrideWith(_DelayedGlobalSubAgents.new),
        ],
      );
      addTearDown(container.dispose);

      var completed = false;
      final resolved = loadRuntimeChatSubAgents(container).then((agents) {
        completed = true;
        return agents;
      });

      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse, reason: '加载中不得降级为空 Agent 列表');

      _DelayedGlobalSubAgents.pending.complete(const [_chronicler]);

      expect(await resolved, const [_chronicler]);
    },
  );

  /// 装配一个已加载、含一条 user 消息、并注入 [agent] 的会话；返回 (sessionId, requestId)。
  ({String sessionId, int requestId}) seedSession(
    ProviderContainer container, {
    required String sessionId,
    required Agent agent,
    String userText = 'hello',
  }) {
    // markLoaded 而非 loadSession：后者读取 aiSettings 会在单测环境异步打开真实
    // App DB，其错误在测试完成后触发并污染后续用例。runTurn 的落库守卫只要求 isLoaded。
    final sessionNotifier = container.read(
      aiChatSessionProvider(sessionId).notifier,
    );
    sessionNotifier.markLoaded();
    sessionNotifier.addUserMessage(userText);

    final runtime = container.read(aiChatRuntimeProvider(sessionId).notifier);
    runtime.agent = agent;
    final requestId = runtime.startRequest();
    return (sessionId: sessionId, requestId: requestId);
  }

  test(
    'cancelled Codemode drains original write without ending a newer request',
    () async {
      final container = buildTestContainer();
      addTearDown(container.dispose);
      // This runner-only fixture models the controller's active session lease.
      final subscription = container.listen(
        aiChatSessionProvider('codemode-cancel'),
        (_, _) {},
      );
      addTearDown(subscription.close);
      final entered = Completer<void>();
      final release = Completer<void>();
      late FakeAgentToolDispatcher dispatcher;
      dispatcher = FakeAgentToolDispatcher(
        tools: {
          'Codemode': FakeAgentTool(
            def: const ToolDef(
              name: 'Codemode',
              description: 'Controlled composite',
              inputSchema: {'type': 'object'},
            ),
            handler: (_, _) async {
              // 真实接线里 orchestrator 的 onRecord 直接写会话状态。
              final session = container.read(
                aiChatSessionProvider('codemode-cancel').notifier,
              );
              session.upsertNestedToolCall(
                'parent',
                const AiNestedToolCall(
                  callId: 'child',
                  toolName: 'Write',
                  effectStatus: AiToolEffectStatus.unknown,
                ),
              );
              entered.complete();
              await release.future;
              session.upsertNestedToolCall(
                'parent',
                const AiNestedToolCall(
                  callId: 'child',
                  toolName: 'Write',
                  status: AiNestedToolStatus.success,
                  effectStatus: AiToolEffectStatus.confirmed,
                  resourceId: 'real-id',
                ),
              );
              return {
                'ok': true,
                'completed_count': 1,
                'completed_operations': [
                  {'call_id': 'child', 'resource_id': 'real-id'},
                ],
              };
            },
          ),
        },
      );
      final agent = FakeAgent.create(
        toolManager: dispatcher,
        responses: const [
          FakeProviderClientResponse.toolCalls([
            ToolCall(
              callId: 'parent',
              toolName: 'Codemode',
              arguments: {'code': 'write'},
            ),
          ]),
        ],
      );
      final seeded = seedSession(
        container,
        sessionId: 'codemode-cancel',
        agent: agent,
      );
      final runtime = container.read(
        aiChatRuntimeProvider(seeded.sessionId).notifier,
      );
      final session = container.read(
        aiChatSessionProvider(seeded.sessionId).notifier,
      );
      var finished = false;
      final turn = buildRunner(container)
          .runTurn(
            'write',
            requestId: seeded.requestId,
            sessionId: seeded.sessionId,
            sourceTurnId: 'original-turn',
          )
          .whenComplete(() {
            finished = true;
            runtime.markRequestIdle(seeded.requestId, notifyOnComplete: false);
          });
      await entered.future;
      await Future<void>.delayed(Duration.zero);
      session.cancelPendingToolCallsForRequest(seeded.requestId);
      runtime.cancelRequest(seeded.requestId);
      session.endStreamingMessage();
      var safeToRollback = false;
      final settled = runtime.waitForRequestCompletion(seeded.requestId).then((
        _,
      ) {
        safeToRollback = true;
      });
      final nextRequest = runtime.startRequest();
      session.addUserMessage('new turn');
      session.startStreamingMessage();
      final newMessageId = container
          .read(aiChatSessionProvider(seeded.sessionId))
          .messages
          .last
          .id;
      session.setWaitingForResponse(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(finished, isFalse);
      expect(safeToRollback, isFalse);
      release.complete();
      expect((await turn).status, ChatTurnStatus.cancelled);
      await settled;
      final state = container.read(aiChatSessionProvider(seeded.sessionId));
      final parent = session.findToolCallByCallId('parent')!.$2;
      expect(parent.status, AiToolCallStatus.cancelled);
      expect(
        parent.nestedCalls.single.effectStatus,
        AiToolEffectStatus.confirmed,
      );
      expect(parent.nestedCalls.single.status, AiNestedToolStatus.success);
      expect(parent.result?['completed_count'], 1);
      expect(
        state.messages
            .singleWhere((message) => message.id == newMessageId)
            .isStreaming,
        isTrue,
      );
      expect(state.isWaitingForResponse, isTrue);
      expect(
        dispatcher.capturedCalls.single.context!.sourceTurnId,
        'original-turn',
      );
      runtime.markRequestIdle(nextRequest, notifyOnComplete: false);
    },
  );

  test('image Run call keeps its tool call for model history replay', () async {
    final container = buildTestContainer();
    addTearDown(container.dispose);
    final subscription = container.listen(
      aiChatSessionProvider('image-replay'),
      (_, _) {},
    );
    addTearDown(subscription.close);
    const args = {
      'command': 'character',
      'subcommand': 'generate-avatar',
      'options': {'character': 'character_1', 'prompt': '白发青年'},
    };
    final dispatcher = FakeAgentToolDispatcher(
      tools: {
        'Run': FakeAgentTool(
          def: const ToolDef(
            name: 'Run',
            description: 'Run',
            inputSchema: {'type': 'object'},
          ),
          handler: (_, _) async => {
            'ok': true,
            'success': true,
            'command': 'character generate-avatar',
            'local_path': 'images/avatar.png',
            'asset_id': 'avatar-asset',
            'character_id': 'character_1',
          },
        ),
      },
    );
    final seeded = seedSession(
      container,
      sessionId: 'image-replay',
      agent: FakeAgent.create(
        toolManager: dispatcher,
        responses: const [
          FakeProviderClientResponse.toolCalls([
            ToolCall(callId: 'avatar', toolName: 'Run', arguments: args),
          ]),
          FakeProviderClientResponse.text('头像已生成'),
        ],
      ),
    );
    final runtime = container.read(
      aiChatRuntimeProvider(seeded.sessionId).notifier,
    );
    final outcome = await buildRunner(container).runTurn(
      '给主角做个头像',
      requestId: seeded.requestId,
      sessionId: seeded.sessionId,
    );
    runtime.markRequestIdle(seeded.requestId, notifyOnComplete: false);
    expect(outcome.isCompleted, isTrue);

    final messages = container
        .read(aiChatSessionProvider(seeded.sessionId))
        .messages;
    final blocks = messages.expand((message) => message.blocks).toList();
    expect(blocks.whereType<AiImageBlock>().single.id, 'img_avatar');
    final toolCall = blocks.whereType<AiToolCallBlock>().single;
    expect(toolCall.callId, 'avatar');
    expect(toolCall.result?['local_path'], 'images/avatar.png');
    expect(toolCall.result?['asset_id'], 'avatar-asset');

    final replay = messages
        .expand(convertAiMessageToAgentMessagesForModel)
        .expand((message) => message.blocks)
        .toList();
    expect(replay.whereType<ToolCallBlock>().single.callId, 'avatar');
    expect(replay.whereType<ToolResultBlock>().single.toolCallId, 'avatar');
  });

  test('rejects a deleted work before configuring chat', () {
    final container = buildTestContainer();
    addTearDown(container.dispose);
    final deleted = testWork(
      'test_work',
      contentKindNovel,
    ).copyWith(deletedAt: DateTime(2026, 9, 10));
    expect(() => buildRunner(container, novel: deleted), throwsStateError);
  });

  for (final kind in [contentKindNovel, contentKindScreenplay]) {
    for (final malformed in [false, true]) {
      test(
        'slash $kind malformed=$malformed request receives current work, source, rules and chosen skill',
        () async {
          final now = DateTime(2026);
          final novel = Novel(
            id: 'current',
            title: 'Current work',
            authorName: '',
            description: '',
            status: 'draft',
            type: 'adaptation',
            contentKind: kind,
            sourceNovelId: 'source_other_kind',
            wordCount: 0,
            category: '',
            tags: const [],
            draft: false,
            createdAt: now,
            updatedAt: now,
            deletedAt: notDeletedSentinel,
          );
          final toolManager = buildTestToolManager(
            workId: novel.id,
            contentKind: kind,
          )..registerAllTools();
          final client = FakeProviderClient(
            responses: const [FakeProviderClientResponse.text('完成')],
          );
          final container = buildTestContainer(
            overrides: [
              installedAgentSkillsProvider.overrideWith(
                () => _FakeInstalledAgentSkillsNotifier([
                  NovelAgentSkillModel(
                    id: 'chosen',
                    sourceKind: AgentSkillSourceKind.novelLocal,
                    name: '我的写法',
                    description: '本次写作',
                    prompt: '保留长句',
                    enabled: true,
                  ),
                ]),
              ),
            ],
          );
          addTearDown(container.dispose);
          final session = seedSession(
            container,
            sessionId: 'slash_$kind',
            agent: FakeAgent.create(),
          );
          final runner = buildRunner(
            container,
            novelId: novel.id,
            novel: novel,
            userRules: '遵守我的表达习惯',
          );
          const invalidPrompt =
              '自定义专家：{{novel_title}}\n{{#screenplay_workspace}}未闭合条件';
          final expert = SubAgent(
            id: 'writer',
            slug: 'writer',
            name: '写手',
            description: '',
            prompt: malformed
                ? invalidPrompt
                : '自定义专家：{{novel_title}}\n'
                      '{{#screenplay_workspace}}场次规则{{/screenplay_workspace}}'
                      '{{^screenplay_workspace}}章节规则{{/screenplay_workspace}}',
            useCustomPrompt: true,
            scope: SubAgentScope.global,
            sortOrder: 0,
          );
          await runner.runSlashCommand(
            _ScopedSkillAiClient(
              toolManager: toolManager,
              providerClient: client,
            ),
            '/写手 使用「我的写法」，只改指定资源，验收事实不变',
            expert,
            requestId: session.requestId,
            sessionId: session.sessionId,
          );
          final request = client.capturedStreamRequests.single;
          final system = request.messages.first.content;
          final renderedPersona = malformed
              ? invalidPrompt
              : '自定义专家：Current work\n${kind == contentKindScreenplay ? '场次规则' : '章节规则'}';
          expect(system, startsWith(renderedPersona));
          expect(request.messages.last.content, contains(renderedPersona));
          for (final text in [system, request.messages.last.content]) {
            if (malformed) {
              expect(text, contains(invalidPrompt));
              continue;
            }
            expect(
              text,
              isNot(contains(kind == contentKindScreenplay ? '章节规则' : '场次规则')),
            );
            expect(text, isNot(contains('{{')));
          }
          expect(system, contains('当前作品工作路径：/works/current'));
          expect(system, contains('原作工作路径：/works/source_other_kind'));
          expect(system, contains('<user_rule>遵守我的表达习惯</user_rule>'));
          expect(system, contains('<name>我的写法</name>'));
          for (final rule in [
            'Read /_schema/{collection}',
            'not_found 后禁止原样重试',
            '从工具结果原样复制，不得自行构造或修改',
            'Create、Write、Edit、Replace、Remove 只能修改当前作品',
          ]) {
            expect(rule.allMatches(system), hasLength(1));
          }
          expect(system, isNot(contains('canvas/{name}')));
          expect(system, isNot(contains('relations/{relation_id}')));
          expect(request.messages.last.content, contains('只改指定资源，验收事实不变'));
        },
      );
    }
  }

  test(
    'late answer and old cancellation cannot resolve a replacement AskUser',
    () async {
      final container = buildTestContainer();
      addTearDown(container.dispose);
      const sessionId = 'ask_replacement';
      final session = container.read(aiChatSessionProvider(sessionId).notifier)
        ..markLoaded();
      session.addUserMessage('hello');
      final runtime = container.read(aiChatRuntimeProvider(sessionId).notifier);
      final oldRun = runtime.startRequest();
      const request = AskUserRequest(
        callId: 'same',
        questions: [AskUserQuestion(id: 'q', question: 'Question')],
      );
      final old = runtime.registerAskUser(request);
      runtime.cancelRequest(oldRun);
      final newRun = runtime.startRequest();
      session.addUserMessage('again');
      final current = runtime.registerAskUser(request);
      old.complete(const AskUserResult(ok: true));
      runtime.cancelRequest(oldRun);
      expect(current.isCompleted, false);
      expect(runtime.pendingAskUserRequests['same'], same(current));
      current.complete(
        const AskUserResult(
          ok: true,
          answers: [AskUserAnswer(questionId: 'q', answer: 'new')],
        ),
      );
      expect((await old.future).resolution, AskUserResolution.interrupted);
      expect((await current.future).answers!.single.answer, 'new');
      expect(runtime.pendingAskUserRequests, isEmpty);
      final blocks = container
          .read(aiChatSessionProvider(sessionId))
          .messages
          .expand((m) => m.blocks)
          .whereType<AiAskUserBlock>()
          .toList();
      expect(blocks.first.status, AiAskUserStatus.interrupted);
      expect(blocks.last.status, AiAskUserStatus.answered);
      runtime.cancelRequest(newRun);
      runtime.markRequestIdle(oldRun);
      runtime.markRequestIdle(newRun);
    },
  );

  test(
    'disposing runtime interrupts pending questions without mutating another provider',
    () async {
      final container = buildTestContainer();
      final runtime = container.read(aiChatRuntimeProvider('dispose').notifier);
      final pending = runtime.registerAskUser(
        const AskUserRequest(callId: 'ask', questions: []),
      );
      container.dispose();
      expect((await pending.future).resolution, AskUserResolution.interrupted);
      expect(runtime.pendingAskUserRequests, isEmpty);
    },
  );

  group('sub-agent completion inputs', () {
    late SpawnAgentRuntimeFixture fixture;
    late ProviderContainer container;
    late AiChatRuntime runtime;
    late AiChatSession session;
    late _CompletionPersistence persistence;
    const path = 'completion-memory';
    var callSequence = 0;

    setUp(() async {
      fixture = SpawnAgentRuntimeFixture();
      await fixture.initialize();
      persistence = _CompletionPersistence(fixture.appDb, 'novel');
      container = buildTestContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(fixture.appDb),
          novelContentDatabaseProvider(path).overrideWithValue(fixture.novelDb),
          aiAgentAutoAcceptProvider.overrideWithValue(false),
          aiSessionPersistenceServiceProvider(
            novelId: 'novel',
            databasePath: path,
          ).overrideWithValue(persistence),
        ],
      );
      session = container.read(aiChatSessionProvider('parent').notifier);
      session.markLoaded();
      session.addUserMessage('Original delegation', id: 'origin');
      session.addUserMessage('New discussion', id: 'current');
      runtime = container.read(aiChatRuntimeProvider('parent').notifier);
      callSequence = 0;
    });

    tearDown(() async {
      container.dispose();
      await fixture.dispose();
    });

    Future<SpawnAgentCompletion> finishChild(
      String turn, {
      bool fail = false,
    }) async {
      final child = fixture.child();
      final run = runtime.startSubAgent(
        handler: child.handler,
        input: {'agent': 'Writer', 'name': 'writer', 'task': 'Write chapter'},
        callId: 'spawn_${callSequence++}',
        context: ToolExecutionContext(
          sourceSessionId: 'parent',
          sourceTurnId: turn,
        ),
        background: true,
      );
      await child.requestEntered.future;
      if (fail) {
        child.response.completeError(StateError('private upstream exception'));
      } else {
        child.finish('Chapter complete');
      }
      await runtime.subAgents.waitForRun(run.runId);
      return container
          .read(aiChatRuntimeProvider('parent'))
          .subAgents
          .pending
          .singleWhere((notice) => notice.run.runId == run.runId);
    }

    test(
      'media operation completion is persisted once and cannot restart after consumption',
      () async {
        final requestId = runtime.startRequest();
        final receipt = await runtime.operations.start(
          context: ToolExecutionContext(
            sessionId: 'parent',
            sourceTurnId: 'origin',
          ),
          callId: 'media-call',
          workId: 'novel',
          kind: 'editing.preview',
          targetPath: '/editings/one',
          toolName: 'Run',
          background: true,
          verifyTarget: () async {},
          execute: (_) async => {
            'ok': true,
            'files': ['preview.mp4'],
          },
        );
        await runtime.operations.wait(
          receipt['run_id'] as String,
          ToolExecutionContext(sessionId: 'parent'),
        );
        final notice = runtime.operations.state.pending.single;
        final client = FakeProviderClient();
        runtime.agent = FakeAgent.create(client: client);
        final runner = buildRunner(
          container,
          novelId: 'novel',
          databasePath: path,
        );
        final outcome = await runner.runTurn(
          '',
          requestId: requestId,
          sessionId: 'parent',
          sourceTurnId: 'origin',
          completionInput: true,
        );
        expect(outcome.isCompleted, true);
        expect(
          client.capturedStreamRequests.single.messages.where(
            (message) => message.id == notice.messageId,
          ),
          hasLength(1),
        );
        expect(runtime.operations.state.pending, isEmpty);
        final saved = await fixture.persistence.loadSessionMessages(
          sessionId: 'parent',
          novelDatabase: fixture.novelDb,
        );
        final reminder = saved.messages.singleWhere(
          (message) => message.id == notice.messageId,
        );
        expect(reminder.type, AiMessageType.system_remind);
        expect(reminder.content, contains('preview.mp4'));
        runtime.markRequestIdle(requestId, notifyOnComplete: false);
        final secondClient = FakeProviderClient();
        runtime.agent = FakeAgent.create(client: secondClient);
        final secondRequest = runtime.startRequest();
        await runner.runTurn(
          '',
          requestId: secondRequest,
          sessionId: 'parent',
          sourceTurnId: 'origin',
          completionInput: true,
        );
        expect(secondClient.streamCallCount, 0);
        runtime.markRequestIdle(secondRequest, notifyOnComplete: false);
      },
    );

    test(
      'busy delivery persists independent reminders and retains current write attribution',
      () async {
        final notices = <SpawnAgentCompletion>[];
        final dispatcher = _TurnIdCapturingDispatcher(
          onTool: (tool) async {
            if (tool == 'T1') {
              notices.add(await finishChild('origin'));
              notices.add(await finishChild('origin', fail: true));
            }
          },
        );
        final client = FakeProviderClient(
          responses: const [
            FakeProviderClientResponse.toolCalls([
              ToolCall(callId: 't1', toolName: 'T1', arguments: {}),
            ]),
            FakeProviderClientResponse.toolCalls([
              ToolCall(callId: 't2', toolName: 'T2', arguments: {}),
            ]),
            FakeProviderClientResponse.text('Reviewed'),
          ],
        );
        runtime.agent = FakeAgent.create(
          client: client,
          toolManager: dispatcher,
        );
        final requestId = runtime.startRequest();
        final outcome =
            await buildRunner(
              container,
              novelId: 'novel',
              databasePath: path,
            ).runTurn(
              'New discussion',
              requestId: requestId,
              sessionId: 'parent',
              userMessageId: 'current',
            );
        runtime.markRequestIdle(requestId);
        expect(outcome.isCompleted, isTrue);
        expect(dispatcher.capturedTurnIds, {'T1': 'current', 'T2': 'current'});
        expect(client.streamCallCount, 3);
        final delivered = client.capturedStreamRequests[1].messages
            .where(
              (message) =>
                  notices.any((notice) => notice.messageId == message.id),
            )
            .toList();
        expect(delivered, hasLength(2));
        expect(delivered.last.content, contains('Status: failed'));
        expect(
          delivered.last.content,
          isNot(contains('private upstream exception')),
        );
        expect(
          container.read(aiChatRuntimeProvider('parent')).subAgents.pending,
          isEmpty,
        );
        for (final notice in notices) {
          expect(runtime.subAgents.takeCompletion(notice.run.runId), isNull);
        }
        final restored = await fixture.persistence.loadSessionMessages(
          sessionId: 'parent',
          novelDatabase: fixture.novelDb,
        );
        final reminders = restored.messages
            .where((message) => message.type == AiMessageType.system_remind)
            .toList();
        expect(
          reminders.map((message) => message.id),
          notices.map((notice) => notice.messageId),
        );
        expect(
          reminders.map((message) => message.content),
          delivered.map((message) => message.content),
        );
        expect(
          restored.messages
              .where(
                (message) =>
                    message.role == AiMessageRole.user &&
                    message.type != AiMessageType.system_remind,
              )
              .map((message) => message.id),
          ['origin', 'current'],
        );
        final replay = restored.messages
            .expand(convertAiMessageToAgentMessagesForModel)
            .toList();
        expect(
          () => preflightProviderHistory(
            replay,
            ProviderHistoryPolicy.openAiChat,
          ),
          returnsNormally,
        );
        expect(
          replay.where(
            (message) =>
                notices.any((notice) => notice.messageId == message.id),
          ),
          hasLength(2),
        );
      },
    );

    test(
      'completion arriving during the final response is consumed before Agent ends',
      () async {
        final requestId = runtime.startRequest();
        SpawnAgentCompletion? notice;
        final client = FakeProviderClient(
          responder: (request) async {
            if (request.callIndex == 0) {
              notice = await finishChild('origin');
              return const FakeProviderClientResponse.text(
                'Current discussion finished',
              );
            }
            return const FakeProviderClientResponse.text(
              'Child result reviewed',
            );
          },
        );
        runtime.agent = FakeAgent.create(client: client);
        final outcome = await buildRunner(container).runTurn(
          'New discussion',
          requestId: requestId,
          sessionId: 'parent',
          userMessageId: 'current',
        );
        expect(outcome.isCompleted, isTrue);
        expect(client.streamCallCount, 2);
        expect(
          client.capturedStreamRequests.last.messages.where(
            (message) => message.id == notice!.messageId,
          ),
          hasLength(1),
        );
        expect(
          container.read(aiChatRuntimeProvider('parent')).requestSequence,
          requestId,
        );
        runtime.markRequestIdle(requestId, notifyOnComplete: false);
      },
    );

    for (final boundary in [
      'before_request',
      'after_beforeLLM',
      'before_done',
    ]) {
      test(
        'cancellation during notification persistence preserves remaining results at $boundary',
        () async {
          container.listen(aiChatSessionProvider('parent'), (_, _) {});
          final requestId = runtime.startRequest();
          final notices = <SpawnAgentCompletion>[];
          Future<void> finishChildren() async {
            notices.add(await finishChild('origin'));
            notices.add(await finishChild('origin'));
          }

          if (boundary == 'before_request') {
            await finishChildren();
          }
          final client = FakeProviderClient(
            responder: (_) async {
              if (boundary == 'before_done') {
                await finishChildren();
              }
              return const FakeProviderClientResponse.text('Current reply');
            },
          );
          runtime.agent = FakeAgent.create(
            client: client,
            hooks: [
              if (boundary == 'after_beforeLLM')
                _BeforeLLMCallback(finishChildren),
            ],
          );
          final savingFirst = Completer<void>();
          final releaseSave = Completer<void>();
          addTearDown(() {
            if (!releaseSave.isCompleted) {
              releaseSave.complete();
            }
          });
          persistence.beforeSave = () async {
            if (!savingFirst.isCompleted &&
                container
                    .read(aiChatSessionProvider('parent'))
                    .messages
                    .any((message) => message.id == notices.first.messageId)) {
              savingFirst.complete();
              await releaseSave.future;
            }
          };
          final runner = buildRunner(
            container,
            novelId: 'novel',
            databasePath: path,
          );
          final processing = runner.runTurn(
            boundary == 'before_request' ? '' : 'New discussion',
            requestId: requestId,
            sessionId: 'parent',
            userMessageId: boundary == 'before_request' ? null : 'current',
            sourceTurnId: boundary == 'before_request' ? 'origin' : 'current',
            completionInput: boundary == 'before_request',
          );
          await savingFirst.future;
          runtime.cancelRequest(
            requestId,
            source: AiChatCancelSource.stopButton,
          );
          releaseSave.complete();
          expect((await processing).isCancelled, isTrue);
          runtime.markRequestIdle(requestId, notifyOnComplete: false);
          expect(client.streamCallCount, boundary == 'before_done' ? 1 : 0);
          expect(
            container.read(aiChatRuntimeProvider('parent')).subAgents.pending,
            [notices.last],
          );
          final saved = await fixture.persistence.loadSessionMessages(
            sessionId: 'parent',
            novelDatabase: fixture.novelDb,
          );
          expect(
            saved.messages
                .where((message) => message.type == AiMessageType.system_remind)
                .map((message) => message.id),
            [notices.first.messageId],
          );

          // 取消后的新 Agent 从已保存历史恢复，再交付剩余结果；两条通知各出现一次。
          persistence.beforeSave = null;
          final resumedClient = FakeProviderClient();
          runtime.agent = FakeAgent.create(
            client: resumedClient,
            initialMessages: saved.messages
                .expand(convertAiMessageToAgentMessagesForModel)
                .toList(),
          );
          final resumedRequestId = runtime.startRequest();
          final resumed = await runner.runTurn(
            '',
            requestId: resumedRequestId,
            sessionId: 'parent',
            sourceTurnId: 'origin',
            completionInput: true,
          );
          runtime.markRequestIdle(resumedRequestId, notifyOnComplete: false);
          expect(resumed.isCompleted, isTrue);
          expect(
            container.read(aiChatRuntimeProvider('parent')).subAgents.pending,
            isEmpty,
          );
          final restored = await fixture.persistence.loadSessionMessages(
            sessionId: 'parent',
            novelDatabase: fixture.novelDb,
          );
          for (final notice in notices) {
            expect(
              resumedClient.capturedStreamRequests.single.messages.where(
                (message) => message.id == notice.messageId,
              ),
              hasLength(1),
            );
            expect(
              restored.messages.where(
                (message) => message.id == notice.messageId,
              ),
              hasLength(1),
            );
          }
        },
      );
    }

    test(
      'notification persistence failure is explicit and preserves unattempted results',
      () async {
        final requestId = runtime.startRequest();
        final notice = await finishChild('origin');
        final unattempted = await finishChild('origin');
        final client = FakeProviderClient();
        runtime.agent = FakeAgent.create(client: client);
        persistence.fail = true;
        final outcome =
            await buildRunner(
              container,
              novelId: 'novel',
              databasePath: path,
            ).runTurn(
              '',
              requestId: requestId,
              sessionId: 'parent',
              sourceTurnId: 'origin',
              completionInput: true,
            );
        expect(outcome.isFailed, isTrue);
        expect(client.streamCallCount, 0);
        expect(runtime.subAgents.takeCompletion(notice.run.runId), isNull);
        expect(
          container.read(aiChatRuntimeProvider('parent')).subAgents.pending,
          [unattempted],
        );
        expect(
          container.read(aiChatRuntimeProvider('parent')).subAgents.runs,
          isEmpty,
        );
        runtime.markRequestIdle(requestId, notifyOnComplete: false);
      },
    );

    for (final acceptUser in [false, true]) {
      test(
        'automatic delivery groups origins; accepted user switches attribution=$acceptUser',
        () async {
          // 先占用入口，保证准备完成通知时测试 runtime 不会被 autoDispose。
          final requestId = runtime.startRequest();
          final first = await finishChild('origin');
          SpawnAgentCompletion? sameOrigin;
          SpawnAgentCompletion? otherOrigin;
          final dispatcher = _TurnIdCapturingDispatcher(
            onTool: (tool) async {
              if (tool != 'T1') {
                return;
              }
              sameOrigin = await finishChild('origin');
              otherOrigin = await finishChild('current');
              if (acceptUser) {
                runtime.stagePendingNextTurnMessage(
                  const QueuedChatMessage(
                    text: 'Accepted user instruction',
                    agentText: 'Accepted user instruction',
                    references: [],
                    sessionId: 'parent',
                    sendOnNextTurn: true,
                  ),
                );
                runtime.agent!.stageNextTurn(
                  'queued_chat',
                  AgentMessage.user(
                    id: 'queued_chat',
                    content: 'Accepted user instruction',
                  ),
                );
              }
            },
          );
          final client = FakeProviderClient(
            responses: const [
              FakeProviderClientResponse.toolCalls([
                ToolCall(callId: 't1', toolName: 'T1', arguments: {}),
              ]),
              FakeProviderClientResponse.toolCalls([
                ToolCall(callId: 't2', toolName: 'T2', arguments: {}),
              ]),
              FakeProviderClientResponse.text('Finished review'),
            ],
          );
          runtime.agent = FakeAgent.create(
            client: client,
            toolManager: dispatcher,
          );
          final outcome =
              await buildRunner(
                container,
                takeQueuedMessage: (_) => runtime.takePendingNextTurnMessage(),
              ).runTurn(
                '',
                requestId: requestId,
                sessionId: 'parent',
                sourceTurnId: 'origin',
                completionInput: true,
              );
          expect(outcome.isCompleted, isTrue);
          final messages = container
              .read(aiChatSessionProvider('parent'))
              .messages;
          final currentTurn = acceptUser
              ? messages
                    .singleWhere(
                      (message) =>
                          message.content == 'Accepted user instruction',
                    )
                    .id
              : 'origin';
          expect(dispatcher.capturedTurnIds, {
            'T1': 'origin',
            'T2': currentTurn,
          });
          expect(
            client.capturedStreamRequests.first.messages
                .where((message) => message.role == AgentMessageRole.user)
                .map((message) => message.id),
            [first.messageId],
          );
          final secondInput = client.capturedStreamRequests[1].messages;
          expect(
            secondInput.where((message) => message.id == sameOrigin!.messageId),
            hasLength(1),
          );
          expect(
            secondInput.where(
              (message) => message.id == otherOrigin!.messageId,
            ),
            hasLength(acceptUser ? 1 : 0),
          );
          expect(
            container.read(aiChatRuntimeProvider('parent')).subAgents.pending,
            hasLength(acceptUser ? 0 : 1),
          );
          expect(
            messages.where(
              (message) =>
                  message.role == AiMessageRole.user &&
                  message.type != AiMessageType.system_remind,
            ),
            hasLength(acceptUser ? 3 : 2),
          );
          runtime.markRequestIdle(requestId);
        },
      );
    }

    test(
      'revoked or removed-origin automatic input cannot make a model request',
      () async {
        final requestId = runtime.startRequest();
        final notice = await finishChild('origin');
        runtime.subAgents.cancelRun(notice.run.runId);
        final orphan = await finishChild('removed-origin');
        final client = FakeProviderClient();
        runtime.agent = FakeAgent.create(client: client);
        await buildRunner(container).runTurn(
          '',
          requestId: requestId,
          sessionId: 'parent',
          sourceTurnId: 'origin',
          completionInput: true,
        );
        expect(client.streamCallCount, 0);
        expect(runtime.subAgents.takeCompletion(orphan.run.runId), isNull);
        expect(
          container.read(aiChatSessionProvider('parent')).messages,
          hasLength(2),
        );
        runtime.markRequestIdle(requestId);
      },
    );
  });

  group('ChatTurnRunner.runTurn characterization', () {
    test(
      'Agent continues after a successful AskUser timeout tool result',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);
        final subscription = container.listen(
          aiChatSessionProvider('ask_continue'),
          (_, _) {},
        );
        addTearDown(subscription.close);
        final manager = buildTestToolManager(
          askUserCallback: (request) async =>
              AskUserResult.timeout(request.questions),
        )..registerAllTools();
        final seeded = seedSession(
          container,
          sessionId: 'ask_continue',
          agent: FakeAgent.create(
            toolManager: manager,
            responses: const [
              FakeProviderClientResponse.toolCalls([
                ToolCall(
                  callId: 'ask_timeout',
                  toolName: 'AskUser',
                  arguments: {
                    'questions': [
                      {'id': 'q', 'question': 'Choose'},
                    ],
                  },
                ),
              ]),
              FakeProviderClientResponse.text(
                'continued using existing context',
              ),
            ],
          ),
        );
        final agent = container
            .read(aiChatRuntimeProvider(seeded.sessionId).notifier)
            .agent!;
        await buildRunner(container).runTurn(
          'hello',
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );
        final messages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        final tool = agent.contextManager.messages
            .expand((m) => m.blocks)
            .whereType<ToolResultBlock>()
            .singleWhere((b) => b.toolCallId == 'ask_timeout');
        expect(tool.isError, false);
        final result =
            jsonDecode((tool.content.single as TextBlock).text) as Map;
        expect(result['resolution'], 'timeout');
        expect(result['unanswered_question_ids'], ['q']);
        expect(
          messages.last.effectiveText,
          contains('continued using existing context'),
        );
        expect(messages.any((m) => m.isStreaming), false);
      },
    );

    test(
      'reports each successful compaction before the turn completes',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        final contextManager = SmartAgentContextManager(
          compactThreshold: 1,
          contextTokens: 100000,
          outputFloor: 1,
        );
        contextManager.summarizer =
            ({required messages, previousSummary, cancellationToken}) async =>
                'summary ${previousSummary ?? ''} ${messages.length}';
        final agent = Agent.custom(
          id: 'compact_test',
          systemPrompt: 'system',
          client: FakeProviderClient(
            responses: const [
              FakeProviderClientResponse.toolCalls([
                ToolCall(
                  callId: 'compact_echo',
                  toolName: 'Echo',
                  arguments: {},
                ),
              ]),
              FakeProviderClientResponse.text('done'),
            ],
          ),
          config: const AgentConfig(),
          toolManager: FakeAgentToolDispatcher.withResults(
            results: {
              'Echo': {'ok': true},
            },
          ),
          contextManager: contextManager,
          initialMessages: [
            AgentMessage.user(id: 'old_user', content: 'old instruction'),
            AgentMessage.assistant(
              id: 'old_assistant',
              content: 'old response',
            ),
          ],
        );
        final seeded = seedSession(
          container,
          sessionId: 'sess_compaction_callbacks',
          agent: agent,
        );
        final observedCounts = <int>[];

        final outcome =
            await buildRunner(
              container,
              onAgentContextCompacted: (agent) {
                observedCounts.add(agent.contextManager.compactionCount);
              },
            ).runTurn(
              'hello',
              requestId: seeded.requestId,
              sessionId: seeded.sessionId,
            );

        expect(outcome.status, ChatTurnStatus.completed);
        expect(observedCounts, [1, 2]);
      },
    );

    test(
      'cancelling during compaction clears the transient compaction state',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        final compactionStarted = Completer<void>();
        final releaseCompaction = Completer<void>();
        final contextManager = SmartAgentContextManager(
          compactThreshold: 1,
          contextTokens: 100000,
          outputFloor: 1,
        );
        contextManager.summarizer =
            ({required messages, previousSummary, cancellationToken}) async {
              compactionStarted.complete();
              await releaseCompaction.future;
              return 'summary';
            };
        final agent = Agent.custom(
          id: 'cancel_during_compaction',
          systemPrompt: 'system',
          client: FakeProviderClient(),
          config: const AgentConfig(),
          toolManager: FakeAgentToolDispatcher(),
          contextManager: contextManager,
          initialMessages: [
            AgentMessage.user(id: 'old_user', content: 'old instruction'),
            AgentMessage.assistant(
              id: 'old_assistant',
              content: 'old response',
            ),
          ],
        );
        final seeded = seedSession(
          container,
          sessionId: 'sess_cancel_compaction',
          agent: agent,
        );

        final outcomeFuture = buildRunner(container).runTurn(
          'hello',
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );
        await compactionStarted.future;
        expect(
          container
              .read(aiChatSessionProvider(seeded.sessionId))
              .isCompactingContext,
          isTrue,
        );

        container
            .read(aiChatRuntimeProvider(seeded.sessionId).notifier)
            .cancelRequest(seeded.requestId);
        releaseCompaction.complete();

        final outcome = await outcomeFuture;
        expect(outcome.status, ChatTurnStatus.cancelled);
        expect(
          container
              .read(aiChatSessionProvider(seeded.sessionId))
              .isCompactingContext,
          isFalse,
        );
      },
    );

    test(
      'plain text turn produces a single completed assistant message',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        final seeded = seedSession(
          container,
          sessionId: 'sess_text',
          agent: FakeAgent.create(
            responses: const [FakeProviderClientResponse.text('Hi there.')],
          ),
        );

        await buildRunner(container).runTurn(
          'hello',
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );

        final messages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        expect(messages.first.role, AiMessageRole.user);
        final assistant = messages.last;
        expect(assistant.role, AiMessageRole.assistant);
        expect(assistant.isStreaming, isFalse);
        expect(assistant.effectiveText, 'Hi there.');
      },
    );

    // PR-2 行为：provider 流内错误不再被当作正常内容吞进 transcript，而是
    // 移除空 assistant + 返回 ChatTurnOutcome.failed，finalText 不含错误文案。
    test(
      'in-stream provider error surfaces as failed outcome, not content',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        final seeded = seedSession(
          container,
          sessionId: 'sess_error',
          // Provider 流抛错 → Agent 捕获并 yield AgentError(友好文案) → runTurn 失败态分支。
          agent: FakeAgent.create(
            responder: (_) => throw StateError('boom-provider-error'),
          ),
        );

        final outcome = await buildRunner(container).runTurn(
          'hello',
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );

        expect(outcome.status, ChatTurnStatus.failed);
        expect(outcome.error?.kind, ChatTurnErrorKind.providerError);
        // finalText 不被错误文案污染。
        expect(outcome.finalText, isEmpty);

        // 失败态：assistant 消息被移除，只有用户消息残留。
        final messages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        expect(messages.length, 1);
        expect(messages.single.role, AiMessageRole.user);
        expect(messages.single.content, 'hello');
      },
    );

    test(
      'exception exit settles running tool calls before history is rebuilt',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        final seeded = seedSession(
          container,
          sessionId: 'sess_exception_with_running_tool',
          agent: FakeAgent.create(
            responder: (_) => throw StateError('provider failed'),
          ),
        );
        final sessionNotifier = container.read(
          aiChatSessionProvider(seeded.sessionId).notifier,
        );
        sessionNotifier.startStreamingMessage();
        sessionNotifier.upsertToolCallBlock(
          AiToolCallBlock(
            id: 'block_interrupted_read',
            callId: 'call_interrupted_read',
            toolName: 'Read',
            arguments: const {'path': '/chapters/1'},
            requestId: seeded.requestId,
            status: AiToolCallStatus.running,
          ),
        );
        sessionNotifier.endStreamingMessage();

        var warningCalls = 0;
        final outcome =
            await buildRunner(
              container,
              onComposerWarning: (_) {
                warningCalls += 1;
                if (warningCalls == 1) {
                  throw StateError('warning callback failed');
                }
              },
            ).runTurn(
              'continue',
              requestId: seeded.requestId,
              sessionId: seeded.sessionId,
            );

        expect(outcome.status, ChatTurnStatus.failed);
        final messages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        final block = messages
            .expand((message) => message.blocks)
            .whereType<AiToolCallBlock>()
            .single;
        expect(block.status, AiToolCallStatus.error);
        expect(
          block.result?['error_code'],
          'turn_ended_before_tool_completion',
        );

        final providerHistory = messages
            .where((message) => !message.isStreaming)
            .expand(convertAiMessageToAgentMessagesForModel)
            .toList(growable: false);
        expect(
          () => preflightProviderHistory(
            providerHistory,
            ProviderHistoryPolicy.openAiChat,
          ),
          returnsNormally,
        );
      },
    );

    test(
      'tool call lifecycle ends in success block with streaming closed',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        final seeded = seedSession(
          container,
          sessionId: 'sess_tool',
          agent: FakeAgent.create(
            toolManager: FakeAgentToolDispatcher.withResults(
              results: {
                'Echo': {'echoed': 'hi'},
              },
            ),
            responses: const [
              FakeProviderClientResponse.toolCalls([
                ToolCall(callId: 'c1', toolName: 'Echo', arguments: {'x': 1}),
              ]),
              FakeProviderClientResponse.text('done'),
            ],
          ),
        );

        await buildRunner(container).runTurn(
          'hello',
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );

        final messages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        final toolBlocks = messages
            .expand((m) => m.blocks)
            .whereType<AiToolCallBlock>()
            .toList();
        expect(toolBlocks, isNotEmpty);
        expect(
          toolBlocks.any((b) => b.status == AiToolCallStatus.success),
          isTrue,
        );
        // 工具终态后所有流式消息都已收口。
        expect(messages.any((m) => m.isStreaming), isFalse);
        expect(messages.last.effectiveText, contains('done'));
      },
    );

    test(
      'SpawnAgent failure details survive parent events persistence and replay',
      () async {
        const sessionId = 'parent_spawn_failure';
        const databasePath = 'in-memory-spawn-failure';
        const failure = {
          'ok': false,
          'error': 'Sub-agent could not complete execution.',
          'error_code': 'spawn_agent_failed',
          'session_id': 'child_spawn_failure',
        };
        const metadata = {'sub_agent_model': 'test-model'};
        final appDb = AppDatabase.forTest(NativeDatabase.memory());
        final novelDb = NovelContentDatabase.forTest(NativeDatabase.memory());
        final container = buildTestContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(appDb),
            novelContentDatabaseProvider(
              databasePath,
            ).overrideWithValue(novelDb),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await novelDb.close();
          await appDb.close();
        });
        var spawnCalls = 0;
        final agent = FakeAgent.create(
          toolManager: FakeAgentToolDispatcher(
            tools: {
              spawnAgentToolName: FakeAgentTool(
                def: ToolDef(
                  name: spawnAgentToolName,
                  description: 'Fake Spawn result',
                  inputSchema: const {'type': 'object'},
                ),
                handler: (_, callId) async {
                  spawnCalls++;
                  // Match the production onSessionStarted callback; the failure
                  // payload must reach the parent through Agent events alone.
                  container
                      .read(aiChatSessionProvider(sessionId).notifier)
                      .patchToolCallByCallId(
                        callId!,
                        result: {'session_id': failure['session_id']},
                      );
                  return {...failure, '_metadata': metadata};
                },
              ),
            },
          ),
          responses: const [
            FakeProviderClientResponse.toolCalls([
              ToolCall(
                callId: 'spawn_1',
                toolName: 'SpawnAgent',
                arguments: {'agent': 'worker', 'task': 'Review the chapter'},
              ),
            ]),
            FakeProviderClientResponse.text('The sub-agent failed.'),
          ],
        );
        final seeded = seedSession(
          container,
          sessionId: sessionId,
          agent: agent,
        );
        await buildRunner(
          container,
          novelId: 'novel_1',
          databasePath: databasePath,
        ).runTurn(
          'Review the chapter',
          requestId: seeded.requestId,
          sessionId: sessionId,
        );
        expect(spawnCalls, 1);
        final liveBlock = container
            .read(aiChatSessionProvider(sessionId))
            .messages
            .expand((message) => message.blocks)
            .whereType<AiToolCallBlock>()
            .single;
        expect(liveBlock.status, AiToolCallStatus.error);
        expect(liveBlock.errorMessage, failure['error']);
        expect(liveBlock.result, failure);
        expect(liveBlock.metadata, metadata);

        final restored = await AiSessionPersistenceService(
          appDb,
          'novel_1',
        ).loadSessionMessages(sessionId: sessionId, novelDatabase: novelDb);
        final persistedBlock = restored.messages
            .expand((message) => message.blocks)
            .whereType<AiToolCallBlock>()
            .single;
        expect(persistedBlock.status, AiToolCallStatus.error);
        expect(persistedBlock.result, failure);
        expect(persistedBlock.metadata, metadata);
        final replay = restored.messages
            .expand(convertAiMessageToAgentMessagesForModel)
            .expand((message) => message.blocks)
            .whereType<ToolResultBlock>()
            .single;
        final liveResult = agent.contextManager.messages
            .expand((message) => message.blocks)
            .whereType<ToolResultBlock>()
            .single;
        expect(replay.isError, isTrue);
        expect(jsonDecode((replay.content.single as TextBlock).text), failure);
        expect(
          (replay.content.single as TextBlock).text,
          (liveResult.content.single as TextBlock).text,
        );
      },
    );

    test(
      'delivered system remind is included in the agent input for the turn',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        final client = FakeProviderClient(
          responses: const [FakeProviderClientResponse.text('ok')],
        );
        final seeded = seedSession(
          container,
          sessionId: 'sess_system_remind',
          agent: FakeAgent.create(client: client),
        );

        // 复刻 ChatSessionController._deliverSystemRemind 的投递：
        // system_remind 类型的 user 消息落会话（持久化/重建回放），warm agent
        // 同步注入 context。remind 必须随本轮请求到达模型。
        const remind = "<system-remind type='slash_subagent_hint' />";
        final remindMessage = container
            .read(aiChatSessionProvider(seeded.sessionId).notifier)
            .addUserMessage(
              remind,
              id: 'system_remind_slash_subagent_hint_1',
              type: AiMessageType.system_remind,
            );
        container
            .read(aiChatRuntimeProvider(seeded.sessionId).notifier)
            .agent
            ?.contextManager
            .addMessages([
              AgentMessage.user(id: remindMessage.id, content: remind),
            ]);

        await buildRunner(container).runTurn(
          'hello',
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );

        final request = client.capturedStreamRequests.single;
        expect(
          request.messages.any(
            (message) => message.content.contains('slash_subagent_hint'),
          ),
          isTrue,
        );
      },
    );

    test('pre-cancelled request renders no assistant message', () async {
      final container = buildTestContainer();
      addTearDown(container.dispose);

      final seeded = seedSession(
        container,
        sessionId: 'sess_cancel',
        agent: FakeAgent.create(
          responses: const [FakeProviderClientResponse.text('unused')],
        ),
      );
      // 在跑 turn 前标记取消：不得重建 Agent 或渲染 assistant 消息。
      container
          .read(aiChatRuntimeProvider(seeded.sessionId).notifier)
          .cancelRequest(seeded.requestId);

      final warnings = <String>[];
      final outcome =
          await buildRunner(container, onComposerWarning: warnings.add).runTurn(
            'hello',
            requestId: seeded.requestId,
            sessionId: seeded.sessionId,
          );

      expect(outcome.status, ChatTurnStatus.cancelled);
      expect(warnings, isEmpty);
      final messages = container
          .read(aiChatSessionProvider(seeded.sessionId))
          .messages;
      expect(messages, hasLength(1));
      expect(messages.single.role, AiMessageRole.user);
    });

    test(
      'cancelled request exception does not show composer warning',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        late ({String sessionId, int requestId}) seeded;
        final seededAgent = FakeAgent.create(
          responder: (_) {
            container
                .read(aiChatRuntimeProvider(seeded.sessionId).notifier)
                .cancelRequest(seeded.requestId);
            throw StateError('provider aborted after user cancel');
          },
        );
        seeded = seedSession(
          container,
          sessionId: 'sess_cancel_exception',
          agent: seededAgent,
        );

        final warnings = <String>[];
        final outcome =
            await buildRunner(
              container,
              onComposerWarning: warnings.add,
            ).runTurn(
              'hello',
              requestId: seeded.requestId,
              sessionId: seeded.sessionId,
            );

        expect(outcome.status, ChatTurnStatus.cancelled);
        expect(warnings, isEmpty);
      },
    );

    test('cancelled request thrown by process does not warn', () async {
      final container = buildTestContainer();
      addTearDown(container.dispose);

      final agent = FakeAgent.create(
        responses: const [
          FakeProviderClientResponse.text(
            'busy',
            eventDelay: Duration(seconds: 1),
          ),
        ],
      );
      final busySubscription = agent.process('busy').listen((_) {});
      addTearDown(busySubscription.cancel);
      await Future<void>.delayed(Duration.zero);

      final seeded = seedSession(
        container,
        sessionId: 'sess_cancel_process_throw',
        agent: agent,
      );
      container
          .read(aiChatRuntimeProvider(seeded.sessionId).notifier)
          .cancelRequest(seeded.requestId);

      final warnings = <String>[];
      final outcome =
          await buildRunner(container, onComposerWarning: warnings.add).runTurn(
            'hello',
            requestId: seeded.requestId,
            sessionId: seeded.sessionId,
          );

      expect(outcome.status, ChatTurnStatus.cancelled);
      expect(warnings, isEmpty);
    });

    test(
      'queued send-now turn attributes tool changes to the new user turn',
      () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        const sessionId = 'sess_turn_attribution';
        late Agent agent;
        final dispatcher = _TurnIdCapturingDispatcher(
          onTool: (name) async {
            if (name != 'T1') {
              return;
            }
            // 模拟工具执行期间用户点「立即发送」：stage 下一轮 user 消息，并把
            // 消费源写入仍存活的 runtime（send-now 的真实链路）。
            agent.stageNextTurn(
              'queued_chat',
              AgentMessage.user(id: 'queued_chat', content: 'second turn'),
            );
            container
                .read(aiChatRuntimeProvider(sessionId).notifier)
                .stagePendingNextTurnMessage(
                  const QueuedChatMessage(
                    text: 'second turn',
                    agentText: 'second turn',
                    references: [],
                    sessionId: sessionId,
                    sendOnNextTurn: true,
                  ),
                );
          },
        );
        agent = Agent.custom(
          id: 'turn_attribution',
          systemPrompt: 'system',
          client: FakeProviderClient(
            responses: const [
              FakeProviderClientResponse.toolCalls([
                ToolCall(callId: 't1', toolName: 'T1', arguments: {}),
              ]),
              FakeProviderClientResponse.toolCalls([
                ToolCall(callId: 't2', toolName: 'T2', arguments: {}),
              ]),
              FakeProviderClientResponse.text('done'),
            ],
            repeatLastResponse: false,
          ),
          config: const AgentConfig(),
          toolManager: dispatcher,
        );

        // 不走 loadSession：其 aiSettings 读取会在单测环境打开真实 App DB。
        // 本用例只需一条 user 消息 + 注入 agent，addUserMessage 即可。
        final sessionNotifier = container.read(
          aiChatSessionProvider(sessionId).notifier,
        );
        final firstUser = sessionNotifier.addUserMessage('first turn');
        final runtime = container.read(
          aiChatRuntimeProvider(sessionId).notifier,
        );
        runtime.agent = agent;
        final requestId = runtime.startRequest();

        final runner = ChatTurnRunner(
          container: container,
          novel: testWork('test_work', contentKindNovel),
          databasePath: null,
          aiPromptService: AiPromptService(),
          promptContext: const AiSessionContext(
            databasePath: null,
            novelName: 'Test Novel',
          ),
          takeQueuedMessage: (turnSessionId) => container
              .read(aiChatRuntimeProvider(turnSessionId).notifier)
              .takePendingNextTurnMessage(),
        );

        await runner.runTurn(
          'first turn',
          requestId: requestId,
          sessionId: sessionId,
          userMessageId: firstUser.id,
        );

        final secondUser = container
            .read(aiChatSessionProvider(sessionId))
            .messages
            .firstWhere(
              (message) =>
                  message.role == AiMessageRole.user &&
                  message.content == 'second turn',
            );

        expect(
          dispatcher.capturedTurnIds['T1'],
          firstUser.id,
          reason: '第一轮工具改动归属触发本次 process 的用户消息',
        );
        expect(secondUser.id, isNot(firstUser.id));
        expect(
          dispatcher.capturedTurnIds['T2'],
          secondUser.id,
          reason: '「立即发送」新一轮的工具改动应归属新消息，而非上一条，回滚才不会错位',
        );
      },
    );

    test(
      'stream retry clears partial bubble and keeps single assistant message',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);

        final client = _FlakyStreamClient([
          _StreamScript(
            events: [TextDelta('partial')],
            error: ClientException('Connection closed while receiving data'),
          ),
          _StreamScript(events: [TextDelta('full'), StreamComplete()]),
        ]);
        final agent = Agent.custom(
          id: 'test',
          systemPrompt: 'Be helpful.',
          client: client,
          config: const AgentConfig(),
          toolManager: FakeAgentToolDispatcher(),
        );
        final seeded = seedSession(
          container,
          sessionId: 'sess_stream_retry',
          agent: agent,
        );
        final observedRetryProgress = <String>[];
        final retrySubscription = container.listen<String>(
          aiChatSessionProvider(
            seeded.sessionId,
          ).select((session) => session.retryProgress),
          (_, next) => observedRetryProgress.add(next),
          fireImmediately: true,
        );
        addTearDown(retrySubscription.close);
        final observedWaitingStates = <bool>[];
        final waitingSubscription = container.listen<bool>(
          aiChatSessionProvider(
            seeded.sessionId,
          ).select((session) => session.isWaitingForResponse),
          (_, next) => observedWaitingStates.add(next),
          fireImmediately: true,
        );
        addTearDown(waitingSubscription.close);

        final outcome = await buildRunner(container).runTurn(
          'hello',
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );

        expect(
          client.calls,
          2,
          reason: 'agent should have retried once then succeeded',
        );
        expect(
          outcome.status,
          ChatTurnStatus.completed,
          reason: 'runTurn should succeed after retry, got ${outcome.status}',
        );
        expect(
          observedWaitingStates,
          containsAllInOrder([false, true, false]),
          reason: '重试等待期间应进入「思考中」瞬态，下一次流事件后自动清除',
        );
        expect(
          container
              .read(aiChatSessionProvider(seeded.sessionId))
              .isWaitingForResponse,
          isFalse,
          reason: 'turn 结束后不得把等待态泄漏到下一轮',
        );
        expect(observedRetryProgress, containsAllInOrder(['', '1/4', '']));
        expect(
          container.read(aiChatSessionProvider(seeded.sessionId)).retryProgress,
          isEmpty,
        );
      },
    );

    test(
      'truncated text continuation persists prefix and continuation separately',
      () async {
        const databasePath = 'in-memory-incomplete-recovery';
        final appDb = AppDatabase.forTest(NativeDatabase.memory());
        final novelDb = NovelContentDatabase.forTest(NativeDatabase.memory());
        final container = buildTestContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(appDb),
            novelContentDatabaseProvider(
              databasePath,
            ).overrideWithValue(novelDb),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await novelDb.close();
          await appDb.close();
        });

        final client = _FlakyStreamClient([
          _StreamScript(
            events: [
              TextDelta('unfinished text'),
              StreamComplete(finishReason: StreamFinishReason.length),
            ],
          ),
          _StreamScript(
            events: [
              TextDelta('final answer'),
              StreamComplete(finishReason: StreamFinishReason.stop),
            ],
          ),
        ]);
        final agent = Agent.custom(
          id: 'incomplete_recovery',
          systemPrompt: 'Be helpful.',
          client: client,
          config: const AgentConfig(),
          toolManager: FakeAgentToolDispatcher(),
        );
        final seeded = seedSession(
          container,
          sessionId: 'sess_incomplete_recovery',
          agent: agent,
        );

        final outcome =
            await buildRunner(
              container,
              novelId: 'novel_1',
              databasePath: databasePath,
            ).runTurn(
              'finish the task',
              requestId: seeded.requestId,
              sessionId: seeded.sessionId,
            );

        expect(client.calls, 2);
        expect(outcome.status, ChatTurnStatus.completed);
        final uiAssistants = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages
            .where((message) => message.role == AiMessageRole.assistant)
            .toList();
        expect(uiAssistants, hasLength(2));
        expect(uiAssistants[0].effectiveText, 'unfinished text');
        expect(uiAssistants[0].isStreaming, isFalse);
        expect(uiAssistants[1].effectiveText, 'final answer');
        expect(uiAssistants[1].isStreaming, isFalse);

        final sessionMessages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        final reminds = sessionMessages
            .where((message) => message.type == AiMessageType.system_remind)
            .toList();
        expect(reminds, hasLength(1));
        expect(reminds.single.content, truncatedResponseContinuationRemind);
        expect(
          sessionMessages.map(
            (message) => '${message.role.name}:${message.type.name}',
          ),
          containsAllInOrder([
            '${AiMessageRole.assistant.name}:${AiMessageType.text.name}',
            '${AiMessageRole.user.name}:${AiMessageType.system_remind.name}',
            '${AiMessageRole.assistant.name}:${AiMessageType.text.name}',
          ]),
        );
        expect(
          groupMessagesForUi(
            sessionMessages,
          ).where((message) => message.role == AiMessageRole.user),
          hasLength(1),
        );

        final persisted = await novelDb.aiChatMessageDao.getBySession(
          seeded.sessionId,
        );
        final persistedAssistants = persisted
            .where((message) => message.role == AiMessageRole.assistant.name)
            .toList();
        expect(persistedAssistants, hasLength(2));
        expect(persistedAssistants[0].content, 'unfinished text');
        expect(persistedAssistants[1].content, 'final answer');
        expect(
          persisted.where(
            (message) => message.type == AiMessageType.system_remind.name,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'terminal incomplete response removes partial bubbles and warns',
      () async {
        final container = buildTestContainer();
        addTearDown(container.dispose);
        final warnings = <String>[];
        final client = _FlakyStreamClient(
          List.generate(
            maxThinkingOnlyRounds,
            (index) => _StreamScript(
              events: [
                ThinkingDelta('unfinished reasoning $index'),
                StreamComplete(finishReason: StreamFinishReason.length),
              ],
            ),
          ),
        );
        final seeded = seedSession(
          container,
          sessionId: 'sess_terminal_incomplete',
          agent: Agent.custom(
            id: 'terminal_incomplete',
            systemPrompt: 'Be helpful.',
            client: client,
            config: const AgentConfig(),
            toolManager: FakeAgentToolDispatcher(),
          ),
        );

        final outcome =
            await buildRunner(
              container,
              onComposerWarning: warnings.add,
            ).runTurn(
              'finish the task',
              requestId: seeded.requestId,
              sessionId: seeded.sessionId,
            );

        expect(outcome.status, ChatTurnStatus.failed);
        expect(warnings, hasLength(1));
        final messages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        expect(
          messages.where(
            (message) =>
                message.role == AiMessageRole.assistant &&
                message.type == AiMessageType.text,
          ),
          isEmpty,
        );
        expect(
          messages.where((message) => message.type == AiMessageType.text),
          hasLength(1),
        );
        expect(messages.first.role, AiMessageRole.user);
        expect(
          messages.where(
            (message) => message.type == AiMessageType.system_remind,
          ),
          hasLength((maxThinkingOnlyRounds - 1) * 2),
        );
      },
    );

    test(
      'thinking-only continuation persists hidden self-talk and user remind',
      () async {
        const databasePath = 'in-memory-thinking-only-remind';
        final appDb = AppDatabase.forTest(NativeDatabase.memory());
        final novelDb = NovelContentDatabase.forTest(NativeDatabase.memory());
        final container = buildTestContainer(
          overrides: [
            appDatabaseProvider.overrideWithValue(appDb),
            novelContentDatabaseProvider(
              databasePath,
            ).overrideWithValue(novelDb),
          ],
        );
        addTearDown(() async {
          container.dispose();
          await novelDb.close();
          await appDb.close();
        });

        final client = _FlakyStreamClient([
          _StreamScript(
            events: [
              ThinkingDelta('long reasoning'),
              SignatureDelta('anthropic-thinking-signature'),
              EncryptedContentDelta('openai-encrypted-reasoning'),
              StreamComplete(finishReason: StreamFinishReason.length),
            ],
          ),
          _StreamScript(
            events: [
              TextDelta('final answer'),
              StreamComplete(finishReason: StreamFinishReason.stop),
            ],
          ),
        ]);
        final seeded = seedSession(
          container,
          sessionId: 'sess_thinking_only_remind',
          agent: Agent.custom(
            id: 'thinking_only_remind',
            systemPrompt: 'Be helpful.',
            client: client,
            config: const AgentConfig(),
            toolManager: FakeAgentToolDispatcher(),
          ),
        );

        final outcome =
            await buildRunner(
              container,
              novelId: 'novel_1',
              databasePath: databasePath,
            ).runTurn(
              'finish the task',
              requestId: seeded.requestId,
              sessionId: seeded.sessionId,
            );

        expect(outcome.status, ChatTurnStatus.completed);
        final sessionMessages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        final reminds = sessionMessages
            .where((message) => message.type == AiMessageType.system_remind)
            .toList();
        expect(reminds, hasLength(2));
        expect(reminds[0].role, AiMessageRole.assistant);
        expect(reminds[0].content, thinkingOnlyContinuationMessage);
        final warmContinuation = client.capturedMessages[1].firstWhere(
          (message) =>
              message.role == AgentMessageRole.assistant &&
              message.content == thinkingOnlyContinuationMessage,
        );
        final warmThinking = warmContinuation.blocks
            .whereType<ThinkingBlock>()
            .single;
        expect(warmThinking.signature, 'anthropic-thinking-signature');
        expect(warmThinking.encryptedContents, ['openai-encrypted-reasoning']);
        expect(reminds[1].role, AiMessageRole.user);
        expect(reminds[1].content, thinkingOnlyContinuationRemind);
        expect(
          groupMessagesForUi(
            sessionMessages,
          ).where((message) => message.role == AiMessageRole.user),
          hasLength(1),
        );
        expect(
          groupMessagesForUi(
            sessionMessages,
          ).where((message) => message.role == AiMessageRole.assistant),
          hasLength(1),
        );

        final persisted = await novelDb.aiChatMessageDao.getBySession(
          seeded.sessionId,
        );
        expect(
          persisted.where(
            (message) => message.type == AiMessageType.system_remind.name,
          ),
          hasLength(2),
        );
        final persistedAssistant = persisted.firstWhere(
          (message) =>
              message.type == AiMessageType.system_remind.name &&
              message.role == AiMessageRole.assistant.name,
        );
        final persistedThinking = persistedAssistant.blocks
            ?.whereType<AiThinkingBlock>()
            .single;
        expect(persistedThinking?.signature, 'anthropic-thinking-signature');
        expect(persistedThinking?.encryptedContents, [
          'openai-encrypted-reasoning',
        ]);

        final restored = convertAiMessageToAgentMessagesForModel(
          AiMessage(
            id: persistedAssistant.id,
            role: AiMessageRole.assistant,
            type: AiMessageType.system_remind,
            content: persistedAssistant.content,
            timestamp: persistedAssistant.createdAt,
            blocks: persistedAssistant.blocks ?? const [],
          ),
        );
        final restoredThinking = restored.single.blocks
            .whereType<ThinkingBlock>()
            .single;
        expect(restoredThinking.signature, 'anthropic-thinking-signature');
        expect(restoredThinking.encryptedContents, [
          'openai-encrypted-reasoning',
        ]);
      },
    );

    test(
      'incomplete tool call exhaustion is hidden and never dispatched',
      () async {
        const sessionId = 'sess_incomplete_tool_call';
        _StreamScript incompleteAttempt(int index) => _StreamScript(
          events: [
            ToolCallDelta(
              callId: 'edit_partial_$index',
              toolName: 'Edit',
              arguments: const {'path': '/chapters/1'},
              isPartial: true,
            ),
            StreamComplete(),
          ],
        );

        final container = buildTestContainer();
        addTearDown(container.dispose);
        final sessionSubscription = container.listen(
          aiChatSessionProvider(sessionId),
          (_, _) {},
        );
        addTearDown(sessionSubscription.close);
        final dispatcher = FakeAgentToolDispatcher();
        final agent = Agent.custom(
          id: 'incomplete_tool_call',
          systemPrompt: 'Be helpful.',
          client: _FlakyStreamClient(
            List.generate(maxThinkingOnlyRounds, incompleteAttempt),
          ),
          config: const AgentConfig(),
          toolManager: dispatcher,
        );
        final seeded = seedSession(
          container,
          sessionId: sessionId,
          agent: agent,
        );

        final outcome = await buildRunner(container).runTurn(
          'edit',
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );

        expect(outcome.status, ChatTurnStatus.failed);
        expect(dispatcher.capturedCalls, isEmpty);
        final messages = container
            .read(aiChatSessionProvider(seeded.sessionId))
            .messages;
        final blocks = messages
            .expand((message) => message.blocks)
            .whereType<AiToolCallBlock>()
            .toList();
        expect(
          blocks,
          isEmpty,
          reason:
              'messages=${messages.map((message) => '${message.role}:'
                  '${message.isStreaming}:${message.content}:'
                  '${message.blocks.map((block) => block.runtimeType).toList()}').toList()}',
        );
      },
    );
  });

  // 已绑定作品的聊天仍从应用全局技能中，只加载可执行的技能。
  group('runSlashCommand skill scope', () {
    test(
      'skillLoader filters app-global skills by isExecutable for the current work',
      () async {
        // 锁定行为:_loadCurrentSkillContext 只读全局 installedAgentSkillsProvider,
        // 且只对 enabled && executionBlockedReason == null 的 skill 返回 prompt。
        final enabledSkill = NovelAgentSkillModel(
          id: 'skill_enabled',
          sourceKind: AgentSkillSourceKind.novelLocal,
          name: 'enabled_skill',
          description: 'desc',
          prompt: 'prompt_enabled',
          enabled: true,
          executionBlockedReason: null,
        );
        final disabledSkill = NovelAgentSkillModel(
          id: 'skill_disabled',
          sourceKind: AgentSkillSourceKind.novelLocal,
          name: 'disabled_skill',
          description: 'desc',
          prompt: 'prompt_disabled',
          enabled: false,
          executionBlockedReason: null,
        );
        final blockedSkill = NovelAgentSkillModel(
          id: 'skill_blocked',
          sourceKind: AgentSkillSourceKind.marketplace,
          name: 'blocked_skill',
          description: 'desc',
          prompt: 'prompt_blocked',
          enabled: true,
          executionBlockedReason: 'revoked_by_marketplace',
        );

        final toolManager = buildTestToolManager();
        // _FlakyStreamClient 没有 script —— subAgent.processText 会抛 RangeError,
        // 但 toolManager.skillLoader 在 processText 之前就已写入,catch 块仅做兜底。
        final aiClient = _ScopedSkillAiClient(
          toolManager: toolManager,
          providerClient: _FlakyStreamClient(const []),
        );

        final container = buildTestContainer(
          overrides: [
            // 单点 override:直接替换 installedAgentSkillsProvider 的 build(),
            // 跳过 DB 链路。技能应用全局,不再按 novelId 过滤。
            installedAgentSkillsProvider.overrideWith(
              () => _FakeInstalledAgentSkillsNotifier([
                enabledSkill,
                disabledSkill,
                blockedSkill,
              ]),
            ),
          ],
        );
        addTearDown(container.dispose);

        // seedSession 只为满足 runSlashCommand 对 aiChatRuntimeProvider 的依赖;
        // runtime.agent 在 runSlashCommand 路径中不会被使用。
        final seeded = seedSession(
          container,
          sessionId: 'sess_skill_scope',
          agent: FakeAgent.create(responses: const []),
        );

        final runner = buildRunner(container);

        await runner.runSlashCommand(
          aiClient,
          'do something',
          SubAgent(
            id: 'sa_skill_scope',
            slug: 'skill_scope',
            name: 'Skill Scope',
            description: 'desc',
            prompt: 'system',
            scope: SubAgentScope.novel,
            sortOrder: 0,
          ),
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );

        // 关键断言:loader 必须按 isExecutable 过滤,而非简单返回所有 skill。
        // 若回归成"返回任意匹配 name 的 skill",disabled/blocked 会泄漏到运行时。
        expect(
          toolManager.skillLoader,
          isNotNull,
          reason: 'runSlashCommand 必须设置 skillLoader',
        );
        expect(
          (await toolManager.skillLoader!('enabled_skill'))?.instructions,
          'prompt_enabled',
        );
        expect(
          await toolManager.skillLoader!('disabled_skill'),
          isNull,
          reason: 'enabled=false 的 skill 不能被运行时执行',
        );
        expect(
          await toolManager.skillLoader!('blocked_skill'),
          isNull,
          reason: 'executionBlockedReason 非 null 的 skill(被撤销)不能被运行时执行',
        );
        expect(
          await toolManager.skillLoader!('unknown_skill'),
          isNull,
          reason: '未安装的 name 应返回 null',
        );
      },
    );

    for (final kind in [contentKindNovel, contentKindScreenplay]) {
      test(
        'screenplay tool guide coexists with custom writing skills in $kind',
        () async {
          final writingSkills = [
            for (final name in ['剧本创作', '剧本写作指南'])
              NovelAgentSkillModel(
                id: 'custom_$name',
                sourceKind: AgentSkillSourceKind.novelLocal,
                name: name,
                description: 'User writing skill',
                prompt: 'User instructions for $name',
                enabled: true,
              ),
          ];
          final toolManager = buildTestToolManager(contentKind: kind);
          final aiClient = _ScopedSkillAiClient(
            toolManager: toolManager,
            providerClient: _FlakyStreamClient(const []),
          );
          final container = buildTestContainer(
            overrides: [
              installedAgentSkillsProvider.overrideWith(
                () => _FakeInstalledAgentSkillsNotifier(writingSkills),
              ),
            ],
          );
          addTearDown(container.dispose);

          final seeded = seedSession(
            container,
            sessionId: 'sess_screenplay_skills_$kind',
            agent: FakeAgent.create(responses: const []),
          );
          final runner = buildRunner(container, contentKind: kind);
          await runner.runSlashCommand(
            aiClient,
            'load writing tools',
            SubAgent(
              id: 'sa_screenplay_skills',
              slug: 'screenplay_skills',
              name: 'Screenplay Skills',
              description: 'desc',
              prompt: 'system',
              scope: SubAgentScope.novel,
              sortOrder: 0,
            ),
            requestId: seeded.requestId,
            sessionId: seeded.sessionId,
          );

          final names = toolManager.skillNamesProvider!();
          for (final skill in writingSkills) {
            expect(names, contains(skill.name));
            expect(
              (await toolManager.skillLoader!(skill.name))?.instructions,
              skill.prompt,
            );
          }
          if (kind == contentKindScreenplay) {
            expect(names, contains('剧本工具使用规范'));
            final guide = await toolManager.skillLoader!('剧本工具使用规范');
            expect(guide, isNotNull);
            expect(guide!.instructions, isNotEmpty);
            expect(
              writingSkills.map((skill) => skill.prompt),
              isNot(contains(guide.instructions)),
            );
          } else {
            expect(names, isNot(contains('剧本工具使用规范')));
          }
        },
      );
    }

    test(
      'bundled 创作向导 exposes its reference descriptors to the Agent',
      () async {
        final toolManager = buildTestToolManager();
        final aiClient = _ScopedSkillAiClient(
          toolManager: toolManager,
          providerClient: _FlakyStreamClient(const []),
        );
        final container = buildTestContainer(
          overrides: [
            installedAgentSkillsProvider.overrideWith(
              () => _FakeInstalledAgentSkillsNotifier(const []),
            ),
          ],
        );
        addTearDown(container.dispose);

        final seeded = seedSession(
          container,
          sessionId: 'sess_bundled_setup_references',
          agent: FakeAgent.create(responses: const []),
        );
        final runner = buildRunner(container);

        await runner.runSlashCommand(
          aiClient,
          'open setup',
          SubAgent(
            id: 'sa_bundled_setup_references',
            slug: 'bundled_setup_references',
            name: 'Bundled Setup References',
            description: 'desc',
            prompt: 'system',
            scope: SubAgentScope.novel,
            sortOrder: 0,
          ),
          requestId: seeded.requestId,
          sessionId: seeded.sessionId,
        );

        final loaded = await toolManager.skillLoader!('创作向导');
        expect(loaded, isNotNull);
        expect(loaded!.references.map((reference) => reference.path), [
          'references/fanfic.md',
          'references/imitation.md',
          'references/original.md',
          'references/sequel.md',
        ]);
      },
    );
  });
}

/// 测试用 [InstalledAgentSkillsNotifier] fake —— 固定返回给定列表,跳过 DB 链路。
class _FakeInstalledAgentSkillsNotifier extends InstalledAgentSkillsNotifier {
  _FakeInstalledAgentSkillsNotifier(this._skills);

  final List<NovelAgentSkillModel> _skills;

  @override
  Future<List<NovelAgentSkillModel>> build() async => _skills;
}
