// 职责: 验证音频渠道按类型固定路由、共用凭据且不改写提示词。
// 关联文件:
//   lib/shared/providers/production_audio.dart
//   lib/shared/services/ai/audio/seed.dart
//   lib/shared/models/audio/request.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/models/audio/exception.dart';
import 'package:reveric/shared/models/audio/request.dart';
import 'package:reveric/shared/providers/production_audio.dart';

void main() {
  test(
    'OpenRouter audio factory shares the channel key and fixed endpoint',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final provider = aiProviderBuiltinById('doubao')!.copyWith(
        type: 'openrouter',
        apiKey: 'shared-key',
        baseUrl: 'https://ignored.invalid',
      );
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final result = await http.runWithClient(
        () => container.read(productionAudioInvokeProvider)(
          provider,
          AudioRequest(
            providerId: provider.id,
            modelId: 'bytedance-seed/seed-audio-1-0',
            prompt: 'rain',
            originalPrompt: 'rain',
          ),
          [],
          Completer<void>().future,
        ),
        () => MockClient((r) async {
          expect(r.url.toString(), 'https://openrouter.ai/api/v1/audio/speech');
          expect(r.headers['Authorization'], 'Bearer shared-key');
          expect((jsonDecode(r.body) as Map)['response_format'], 'pcm');
          return http.Response.bytes(
            bytes,
            200,
            headers: {'content-type': 'audio/pcm;rate=24000;channels=1'},
          );
        }),
      );
      expect(result.bytes.sublist(44), bytes);
    },
  );

  final wav = Uint8List(44)
    ..setRange(0, 4, ascii.encode('RIFF'))
    ..setRange(8, 12, ascii.encode('WAVE'));

  for (final (type, host) in [('volcengine', 'openspeech.bytedance.com')]) {
    for (final status in [200, 401]) {
      test('$type routes audio to $host and handles HTTP $status', () async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final provider = aiProviderBuiltinById('doubao')!.copyWith(
          type: type,
          baseUrl: 'https://override.example/v1',
          apiKey: 'shared-key',
          audioModels: ['seed-audio-1.0'],
        );
        const prompt = 'Let @Audio1 speak, then @音频1 laugh.';
        final request = AudioRequest(
          providerId: provider.id,
          modelId: 'seed-audio-1.0',
          originalPrompt: prompt,
          prompt: prompt,
          references: [
            AudioReference(
              assetId: 'voice.wav',
              kind: 'audio',
              mimeType: 'audio/wav',
              bytes: wav.length,
              durationMs: 1000,
            ),
          ],
        );
        var calls = 0;
        final pending = http.runWithClient(
          () => container.read(productionAudioInvokeProvider)(
            provider,
            request,
            [wav],
            Completer<void>().future,
          ),
          () => MockClient((r) async {
            calls++;
            expect(r.url.toString(), 'https://$host/api/v3/tts/create');
            expect(r.headers['X-Api-Key'], 'shared-key');
            expect(jsonDecode(r.body), {
              'model': 'seed-audio-1.0',
              'text_prompt': prompt,
              'references': [
                {'audio_data': base64Encode(wav)},
              ],
              'audio_config': {'format': 'wav', 'sample_rate': 24000},
            });
            return http.Response(
              jsonEncode(
                status == 200
                    ? {'audio': base64Encode(wav)}
                    : {'message': 'Unauthorized'},
              ),
              status,
            );
          }),
        );
        if (status == 200) {
          expect((await pending).bytes, wav);
        } else {
          await expectLater(
            pending,
            throwsA(
              isA<AudioException>().having(
                (e) => e.code,
                'code',
                'authentication',
              ),
            ),
          );
        }
        expect(calls, 1);
        expect(request.prompt, prompt);
      });
    }
  }
}
