// 职责: 验证议会主持模式 — 被点名者优先接话、作者插话中点名的成员先回答、单人点名发言、成员只收到自己上次发言之后的新内容。
// 关联文件:
//   lib/shared/services/ai/agent_council_orchestrator.dart
//   lib/shared/agent/agent_orchestrator.dart
//   lib/shared/models/agent_council_models.dart
//   lib/shared/agent/fake_agent.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/agent/agent_hook.dart';
import 'package:reveric/shared/agent/client.dart' show ProviderClient;
import 'package:reveric/shared/agent/fake_agent.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/models/agent_council_models.dart';
import 'package:reveric/shared/models/ai_chat_models.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/services/ai/agent_council_orchestrator.dart';
import 'package:reveric/shared/services/ai/chat.dart';
import 'package:reveric/shared/services/ai/prompt_template.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';

const _context = AiSessionContext(workId: 'novel', contentKind: 'novel');

class _CouncilAiClient extends AiClient {
  _CouncilAiClient(this.fakeClient, this.fakeToolManager)
    : super(aiProviderBuiltinDefaults.first, chatModel: 'test-model');

  final FakeProviderClient fakeClient;
  final AiToolManager fakeToolManager;

  @override
  ProviderClient get providerClient => fakeClient;

  @override
  AiToolManager? get toolManager => fakeToolManager;

  @override
  Future<String> chatCompletionDetached(
    List<AiMessage> messages, {
    required Duration timeout,
    AiSessionContext? context,
    List<AgentHook> hooks = const [],
  }) async => 'Title';
}

CouncilParticipant _member(String name) => CouncilParticipant(
  id: name.toLowerCase(),
  name: name,
  description: '',
  prompt: '',
);

final _alice = _member('Alice');
final _bob = _member('Bob');
final _carol = _member('Carol');

String _task(FakeProviderClientRequest request) =>
    request.messages.last.content;

String _speakerOf(FakeProviderClientRequest request) =>
    RegExp(r'## 当前发言者：(\S+)').firstMatch(_task(request))!.group(1)!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NovelContentDatabase contentDb;
  late AppDatabase appDb;
  late AiToolManager toolManager;

  setUpAll(PromptTemplateService.loadAll);

  setUp(() {
    contentDb = NovelContentDatabase.forTest(NativeDatabase.memory());
    appDb = AppDatabase.forTest(NativeDatabase.memory());
    final contentService = NovelContentService(contentDb);
    final overlay = WorkingOverlayService(
      contentDb,
      contentService,
      novelActionsService: NovelActionsService(appDb),
    );
    toolManager = AiToolManager(
      contentService,
      workingOverlayService: overlay,
      workId: _context.workId,
      contentKind: _context.contentKind,
    )..registerAllTools();
  });

  tearDown(() async {
    await contentDb.close();
    await appDb.close();
  });

  ({_CouncilAiClient client, List<FakeProviderClientRequest> requests}) client(
    String Function(String speaker, String task) reply,
  ) {
    final requests = <FakeProviderClientRequest>[];
    final fake = FakeProviderClient(
      responder: (request) {
        requests.add(request);
        return FakeProviderClientResponse.text(
          reply(_speakerOf(request), _task(request)),
        );
      },
    );
    return (client: _CouncilAiClient(fake, toolManager), requests: requests);
  }

  Future<AgentCouncilSession> discuss(
    AgentCouncilOrchestrator orchestrator,
    AiClient aiService, {
    int rounds = 1,
  }) {
    return orchestrator.startDiscussion(
      novelId: 'novel',
      topic: 'Topic',
      participants: [_alice, _bob, _carol],
      aiService: aiService,
      context: _context,
      config: AgentCouncilConfig(maxRounds: rounds, autoSummarize: false),
    );
  }

  List<String> speakers(AgentCouncilSession session) => [
    for (final r in session.rounds)
      for (final m in r.messages) m.participantName,
  ];

  test('a member named at the end of a turn speaks next, tag hidden', () async {
    final fake = client(
      (speaker, _) =>
          speaker == 'Alice' ? 'Carol 的方案有漏洞。\n【请回应】Carol' : '$speaker 发言',
    );
    final session = await discuss(AgentCouncilOrchestrator(), fake.client);

    expect(speakers(session), ['Alice', 'Carol', 'Bob']);
    final first = session.rounds.single.messages.first;
    expect(first.content, 'Carol 的方案有漏洞。');
    expect(first.addresseeId, 'carol');
  });

  test(
    'author interjection mentioning a member makes them answer first',
    () async {
      final orchestrator = AgentCouncilOrchestrator();
      final fake = client((speaker, _) {
        if (speaker == 'Alice') {
          orchestrator.queueUserMessage(
            CouncilMessage(
              id: 'user_1',
              participantId: councilUserParticipantId,
              participantName: '你',
              content: 'Carol 你怎么看？',
              timestamp: DateTime(2026, 10, 2),
              round: 1,
            ),
          );
        }
        return '$speaker 发言';
      });
      final session = await discuss(orchestrator, fake.client);

      expect(speakers(session), ['Alice', '你', 'Carol', 'Bob']);
      final carolTask = fake.requests
          .map(_task)
          .firstWhere((t) => t.contains('当前发言者：Carol'));
      expect(carolTask, contains('作者：Carol 你怎么看？'));
    },
  );

  test('solo speaker appends to the last round', () async {
    final orchestrator = AgentCouncilOrchestrator();
    final fake = client((speaker, _) => '$speaker 发言');
    final first = await discuss(orchestrator, fake.client);
    orchestrator.finishRun();

    final next = await orchestrator.runRound(
      session: first,
      aiService: fake.client,
      context: _context,
      speakerId: 'bob',
    );

    expect(next.rounds, hasLength(1));
    expect(speakers(next), ['Alice', 'Bob', 'Carol', 'Bob']);
  });

  test(
    'members with memory only get what was said since their last turn',
    () async {
      final orchestrator = AgentCouncilOrchestrator();
      final fake = client((speaker, _) => '$speaker 第一轮观点');
      await discuss(orchestrator, fake.client, rounds: 2);

      final aliceTasks = fake.requests
          .map(_task)
          .where((t) => t.contains('当前发言者：Alice'))
          .toList();
      expect(aliceTasks, hasLength(2));
      final second = aliceTasks.last;
      expect(second, contains('你上次发言之后的新发言'));
      expect(second, contains('Bob：Bob 第一轮观点'));
      expect(second, isNot(contains('Alice：Alice 第一轮观点')));
      expect(second, isNot(contains('## 前人发言')));
    },
  );

  test(
    'history edits drop member memory so the next turn sees everything',
    () async {
      final orchestrator = AgentCouncilOrchestrator();
      final fake = client((speaker, _) => '$speaker 观点');
      final first = await discuss(orchestrator, fake.client);
      orchestrator.finishRun();
      orchestrator.forgetTranscripts();

      await orchestrator.runRound(
        session: first,
        aiService: fake.client,
        context: _context,
      );
      final aliceTask = fake.requests
          .map(_task)
          .lastWhere((t) => t.contains('当前发言者：Alice'));
      expect(aliceTask, contains('## 前人发言'));
      expect(aliceTask, contains('Alice：Alice 观点'));
    },
  );
}
