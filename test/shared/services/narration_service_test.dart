// 职责: 验证朗读配置持久化、供应商可用性校验及角色音色到语音请求的映射。
// 关联文件:
//   lib/shared/services/screenplay/narration_service.dart
//   lib/shared/models/narration.dart

import 'dart:async';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/models/audio/exception.dart';
import 'package:reveric/shared/models/audio/request.dart';
import 'package:reveric/shared/models/audio/result.dart';
import 'package:reveric/shared/models/narration.dart';
import 'package:reveric/shared/services/screenplay/narration_service.dart';

const narrationModel = 'google/gemini-3.8-flash-tts';

Future<void> insertNarrationProvider(AppDatabase db) => db
    .into(db.aiProviders)
    .insert(
      AiProvidersCompanion.insert(
        id: 'speech',
        name: 'Speech',
        type: 'openrouter',
        enabled: const Value(true),
        apiKey: const Value('test-key'),
        audioModels: const Value([narrationModel]),
      ),
    )
    .then((_) {});

void main() {
  late AppDatabase db;
  late NarrationService service;
  late List<AudioRequest> requests;
  final settings = NarrationSettings(
    providerId: 'speech',
    modelId: narrationModel,
    narrator: 'Kore',
    voices: {'a': 'Puck'},
  );
  const segment = NarrationSegment(
    text: '别走。',
    voice: 'Puck',
    sceneId: 's',
    characterId: 'a',
    instructions: '轻声',
  );
  setUp(() async {
    db = AppDatabase.forTest(NativeDatabase.memory());
    await insertNarrationProvider(db);
    requests = [];
    service = NarrationService(
      database: db,
      invoke: (provider, request, references, abort) async {
        requests.add(request);
        expect(references, isEmpty);
        return AudioGenerationResult(Uint8List.fromList([1, 2]));
      },
    );
  });
  tearDown(() => db.close());

  test(
    'per-work configuration round trips without changing character data',
    () async {
      expect((await service.load('new')).modelId, isEmpty);
      await service.save('work', settings);
      final restored = await service.load('work');
      expect(restored.toJson(), settings.toJson());
      expect((await service.load('other')).modelId, isEmpty);
    },
  );

  test(
    'generation preserves dialogue and passes voice and direction separately',
    () async {
      final audio = await service.generate(
        settings,
        segment,
        Completer<void>().future,
      );
      expect(audio.extension, 'mp3');
      expect(requests.single.prompt, '别走。');
      expect(requests.single.parameters.voice, 'Puck');
      expect(requests.single.parameters.instructions, '轻声');
    },
  );

  test('disabled provider stops before billable invocation', () async {
    final provider = (await db.aiProviderDao.getById('speech'))!;
    await db.aiProviderDao.upsert(provider.copyWith(enabled: false));
    await expectLater(
      service.generate(settings, segment, Completer<void>().future),
      throwsA(isA<AudioException>()),
    );
    expect(requests, isEmpty);
  });

  test('already cancelled generation does not submit or retry', () async {
    final abort = Completer<void>()..complete();
    await expectLater(
      service.generate(settings, segment, abort.future),
      throwsA(isA<AudioException>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(requests, isEmpty);
  });
}
