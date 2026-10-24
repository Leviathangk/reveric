// 职责: 持久化作品朗读配置并校验供应商与模型后调用既有语音生成接口。
// 关联文件:
//   lib/shared/providers/narration.dart
//   lib/shared/models/narration.dart
//   lib/shared/services/screenplay/narration_orchestrator.dart
//   lib/shared/services/production/audio_generate_orchestrator.dart

import 'dart:async';
import 'dart:convert';
import '../../database/app_database.dart';
import '../../logger/app_logger.dart';
import '../../models/audio/channels.dart';
import '../../models/audio/exception.dart';
import '../../models/audio/request.dart';
import '../../models/narration.dart';
import '../production/audio_generate_orchestrator.dart';
import 'narration_orchestrator.dart';

class NarrationService {
  NarrationService({required this.database, required this.invoke});
  final AppDatabase database;
  final ProductionAudioInvoke invoke;

  Future<NarrationSettings> load(String workId) async {
    final raw = await database.appStateDao.get('screenplay_narration:$workId');
    return raw == null
        ? NarrationSettings()
        : NarrationSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> save(String workId, NarrationSettings settings) async {
    await requireProvider(settings);
    if (settings.narrator.trim().isEmpty) {
      throw const AudioException('audio_voice_required');
    }
    try {
      await database.appStateDao.set(
        key: 'screenplay_narration:$workId',
        value: jsonEncode(settings.toJson()),
      );
    } catch (error, stack) {
      AppLogger.error(
        '[DB] UPSERT app_states screenplay_narration:$workId',
        error: error,
        stackTrace: stack,
      );
      rethrow;
    }
  }

  Future<AiProvider> requireProvider(NarrationSettings settings) async {
    final provider = await database.aiProviderDao.getById(settings.providerId);
    if (provider == null ||
        !provider.enabled ||
        !provider.audioModels.contains(settings.modelId) ||
        lookupAudioChannelModel(
              provider.type,
              settings.modelId,
            )?.capabilities.speech !=
            true) {
      throw const AudioException('invalid_config');
    }
    return provider;
  }

  Future<NarrationAudio> generate(
    NarrationSettings settings,
    NarrationSegment segment,
    Future<void> abort,
  ) async {
    var cancelled = false;
    unawaited(abort.then((_) => cancelled = true));
    final provider = await requireProvider(settings);
    if (cancelled) {
      throw const AudioException('cancelled');
    }
    final request = resolveAudioRequest(
      provider.type,
      AudioRequest(
        providerId: provider.id,
        modelId: settings.modelId,
        prompt: segment.text,
        originalPrompt: segment.text,
        parameters: AudioRequestDefaults(
          voice: ConfigValue(segment.voice),
          instructions: ConfigValue(segment.instructions),
        ),
      ),
    );
    final result = await invoke(provider, request, const [], abort);
    if (cancelled) {
      throw const AudioException('cancelled');
    }
    if (result.bytes.isEmpty) {
      throw const AudioException('invalid_result');
    }
    return NarrationAudio(
      result.bytes,
      audioOutputFileFormat(request.parameters.responseFormat),
    );
  }
}
