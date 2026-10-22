// 职责: 组合音频渠道的型号映射、能力覆盖、请求默认值与协议要求，并按 provider 类型查找渠道型号。
// 关联文件:
//   lib/shared/models/audio/catalog.dart
//   lib/shared/models/audio/config.dart
//   lib/shared/models/audio/request.dart
//   lib/shared/models/ai_provider.dart

import '../ai_provider.dart' show ModelIdSource, aiProviderTypeConfigFor;
import 'catalog.dart';

enum AudioProtocol { seed_audio, minimax_music, openrouter_speech }

class AudioProtocolOptions {
  const AudioProtocolOptions({
    this.requiresAllAudioReferencesMentioned = false,
  });
  final bool requiresAllAudioReferencesMentioned;
}

class AudioChannelModel {
  const AudioChannelModel({
    required this.catalogId,
    AudioModelCapabilities capabilities = const AudioModelCapabilities(),
    AudioRequestDefaults requestDefaults = const AudioRequestDefaults(),
    this.protocolOptions = const AudioProtocolOptions(),
  }) : _capabilities = capabilities,
       _requestDefaults = requestDefaults;
  final String catalogId;
  final AudioModelCapabilities _capabilities;
  final AudioRequestDefaults _requestDefaults;
  final AudioProtocolOptions protocolOptions;
  AudioModelCatalogEntry get model => audioModelsCatalog[catalogId]!;
  AudioModelCapabilities get capabilities =>
      model.capabilities.merge(_capabilities);
  AudioRequestDefaults get requestDefaults =>
      model.requestDefaults.merge(_requestDefaults);
}

const audioChannelModels = <AudioProtocol, Map<String, AudioChannelModel>>{
  AudioProtocol.seed_audio: {
    'seed-audio-1.0': AudioChannelModel(catalogId: 'seed-audio-1.0'),
  },
  AudioProtocol.minimax_music: {
    'music-3.0': AudioChannelModel(catalogId: 'music-3.0'),
    'music-2.6': AudioChannelModel(catalogId: 'music-2.6'),
  },
  AudioProtocol.openrouter_speech: {
    'bytedance-seed/seed-audio-1-0': AudioChannelModel(
      catalogId: 'seed-audio-1.0',
      capabilities: AudioModelCapabilities(
        references: {
          'audio': AudioReferenceLimits(
            mimeTypes: {'audio/wav', 'audio/x-wav', 'audio/mpeg', 'audio/ogg'},
          ),
        },
      ),
      // PCM rate and channels come from response headers, not a request option.
      requestDefaults: AudioRequestDefaults(
        responseFormat: ConfigValue('pcm'),
        sampleRate: ConfigValue(null),
      ),
      protocolOptions: AudioProtocolOptions(
        requiresAllAudioReferencesMentioned: true,
      ),
    ),
  },
};

/// 按 provider 类型查找渠道型号：先精确匹配渠道 ID；可接中转站的渠道再从 ID
/// 中识别目录型号。找不到时返回 null，是否允许使用由业务层决定。
AudioChannelModel? lookupAudioChannelModel(
  String providerType,
  String? modelId,
) {
  final config = aiProviderTypeConfigFor(providerType);
  final models = audioChannelModels[config?.audioProtocol];
  if (config == null || models == null) {
    return null;
  }
  final exact = models[modelId?.trim()];
  if (exact != null || config.modelIdSource == ModelIdSource.registered) {
    return exact;
  }
  final catalogId = recognizeAudioModel(modelId);
  return models.values
      .where((channel) => channel.catalogId == catalogId)
      .firstOrNull;
}

List<String> audioModelsForProvider(String providerType) =>
    audioChannelModels[aiProviderTypeConfigFor(providerType)?.audioProtocol]
        ?.keys
        .toList(growable: false) ??
    const [];
