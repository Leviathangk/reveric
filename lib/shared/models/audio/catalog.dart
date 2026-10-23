// 职责: 维护独立于渠道的音频型号、能力与共用请求默认值。
// 关联文件:
//   lib/shared/models/audio/config.dart
//   lib/shared/models/audio/channels.dart

import '../model_config.dart' show ModelIdRecognizer;
import 'config.dart';
import 'speech.dart';
export 'config.dart';

class AudioModelCatalogEntry {
  const AudioModelCatalogEntry({
    required this.capabilities,
    required this.requestDefaults,
    this.aliases = const {},
  });
  final AudioModelCapabilities capabilities;
  final AudioRequestDefaults requestDefaults;
  final Set<String> aliases;
}

const _minimaxMusicModel = AudioModelCatalogEntry(
  capabilities: AudioModelCapabilities(maxPromptCharacters: 2000),
  requestDefaults: AudioRequestDefaults(
    responseFormat: ConfigValue('mp3'),
    sampleRate: ConfigValue(44100),
    bitrate: ConfigValue(256000),
  ),
);

// https://docs.byteplus.com/en/docs/byteplusvoice/seedaudio-01
// https://platform.minimax.io/docs/api-reference/music-generation
final audioModelsCatalog = <String, AudioModelCatalogEntry>{
  'seed-audio-1.0': AudioModelCatalogEntry(
    capabilities: AudioModelCapabilities(
      maxPromptCharacters: 3000,
      maxOutputDurationMs: ConfigValue(120000),
      supportsAudioReferencePlaceholders: true,
      references: {
        'audio': AudioReferenceLimits(
          maxCount: 3,
          maxBytes: 10 * 1024 * 1024,
          maxDurationMs: ConfigValue(30000),
          mimeTypes: {
            'audio/wav',
            'audio/x-wav',
            'audio/mpeg',
            'audio/pcm',
            'audio/ogg',
          },
        ),
        'image': AudioReferenceLimits(
          maxCount: 1,
          maxBytes: 10 * 1024 * 1024,
          mimeTypes: {'image/jpeg', 'image/png', 'image/webp'},
        ),
      },
    ),
    requestDefaults: AudioRequestDefaults(
      responseFormat: ConfigValue('wav'),
      sampleRate: ConfigValue(24000),
    ),
  ),
  for (final entry in speechModels.entries)
    entry.key: AudioModelCatalogEntry(
      capabilities: entry.value,
      requestDefaults: AudioRequestDefaults(responseFormat: ConfigValue('mp3')),
    ),
  'music-3.0': _minimaxMusicModel,
  'music-2.6': _minimaxMusicModel,
};

final _audioModelRecognizer = ModelIdRecognizer({
  for (final entry in audioModelsCatalog.entries)
    entry.key: entry.value.aliases,
});

/// 渠道型号 ID 对应的目录 ID；规则见 [ModelIdRecognizer]。
String? recognizeAudioModel(String? modelId) =>
    _audioModelRecognizer.recognize(modelId);

AudioModelCatalogEntry? lookupAudioModel(String? modelId) =>
    audioModelsCatalog[recognizeAudioModel(modelId)];
