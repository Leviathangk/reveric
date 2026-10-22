// 职责: 验证浮窗聊天失败时保留工具结果，并通过共享日志记录诊断。
// 关联文件:
//   lib/shared/services/floating_chat_service.dart
//   lib/shared/logger/app_logger.dart
//   lib/shared/database/app_database.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/agent/agent_event.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/services/floating_chat_service.dart';

void main() {
  late AppDatabase database;
  late FloatingChatService service;
  late DebugPrintCallback originalDebugPrint;
  late List<String> messages;
  late _AsyncFailingStderr unavailableStderr;

  setUp(() async {
    messages = [];
    originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) {
        messages.add(message);
      }
    };
    unavailableStderr = _AsyncFailingStderr();
    database = AppDatabase.forTest(
      NativeDatabase.memory(
        // 缺表的测试库让两个作品查询入口产生真实 SQLite 异常。
        setup: (raw) =>
            raw.execute('PRAGMA user_version = ${database.schemaVersion}'),
      ),
    );
    service = FloatingChatService(
      config: aiProviderBuiltinById('deepseek')!.copyWith(
        apiKey: 'test-key',
        baseUrl: 'https://provider.invalid/v1',
        models: ['test-model'],
      ),
      database: database,
    );
    await http.runWithClient(
      service.initialize,
      () => MockClient((_) async => throw StateError('Unexpected request')),
    );
    messages.clear();
  });

  tearDown(() async {
    service.dispose();
    await database.close();
    debugPrint = originalDebugPrint;
  });

  for (final (tool, input, expectedError) in [
    ('WebSearch', {'query': 'test'}, 'Web search is temporarily unavailable.'),
    (
      'WebFetch',
      {'url': 'https://example.invalid/page'},
      'Web fetch is temporarily unavailable.',
    ),
    ('SearchNovels', {'query': 'test'}, 'Novel search failed.'),
    (
      'SearchNovelContent',
      {'novelId': 'test-novel', 'query': 'test'},
      'Content search failed.',
    ),
  ]) {
    test('$tool logs failure without writing to stderr', () async {
      final result = await http.runWithClient(
        () => IOOverrides.runZoned(
          () => service.executeTool(name: tool, input: input),
          stderr: () => unavailableStderr,
        ),
        () =>
            MockClient((_) async => http.Response('upstream unavailable', 503)),
      );

      expect(result['error'], expectedError);
      expect(unavailableStderr.writeCount, 0);
      final diagnostic = messages.join('\n');
      expect(diagnostic, contains('[FloatingChat]'));
      expect(diagnostic, contains(tool));
      if (tool.startsWith('Web')) {
        expect(diagnostic, contains('url=https://'));
        expect(diagnostic, contains('status=503'));
        expect(diagnostic, contains('body=upstream unavailable'));
      } else {
        expect(diagnostic, contains('no such table: novels'));
      }
    });
  }

  test('busy agent logs failure without writing to stderr', () async {
    await http.runWithClient(() async {
      final firstRun = StreamIterator(service.chatStream('first request'));
      try {
        expect(await firstRun.moveNext(), isTrue);
        expect(firstRun.current, isA<AgentStart>());
        final events = await IOOverrides.runZoned(
          () => service.chatStream('second request').toList(),
          stderr: () => unavailableStderr,
        );

        expect(events, hasLength(1));
        final error = events.single as AgentError;
        expect(error.technicalMessage, contains('already processing'));
        expect(unavailableStderr.writeCount, 0);
        expect(messages.join('\n'), contains('[FloatingChat] agent error'));
        expect(messages.join('\n'), contains('already processing'));
      } finally {
        await firstRun.cancel();
      }
    }, () => MockClient((_) async => throw StateError('Unexpected request')));
  });
}

// 模拟 Windows GUI 的无效标准错误句柄，写入失败异步冒泡。
class _AsyncFailingStderr implements Stdout {
  var writeCount = 0;

  @override
  void writeln([Object? object = '']) {
    writeCount += 1;
    unawaited(
      Future<void>.error(
        const FileSystemException(
          'writeFrom failed',
          '',
          OSError('The handle is invalid', 6),
        ),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
