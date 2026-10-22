// 职责: 定义音频模型与渠道共用的能力和请求默认值，并按字段合并覆盖项。
// 关联文件:
//   lib/shared/models/audio/catalog.dart
//   lib/shared/models/audio/channels.dart
//   lib/shared/models/audio/request.dart
//   lib/shared/models/model_config.dart

import '../model_config.dart';
export '../model_config.dart' show ConfigValue;

class AudioReferenceLimits {
  const AudioReferenceLimits({
    int? maxCount,
    Set<String>? mimeTypes,
    int? maxBytes,
    ConfigValue<int>? maxDurationMs,
  }) : _maxCount = maxCount,
       _mimeTypes = mimeTypes,
       _maxBytes = maxBytes,
       _maxDurationMs = maxDurationMs;

  final int? _maxCount;
  int get maxCount => _maxCount ?? 0;
  final Set<String>? _mimeTypes;
  Set<String> get mimeTypes => _mimeTypes ?? const {};
  final int? _maxBytes;
  int get maxBytes => _maxBytes ?? 0;
  final ConfigValue<int>? _maxDurationMs;
  int? get maxDurationMs => _maxDurationMs?.value;

  AudioReferenceLimits merge(AudioReferenceLimits overrides) =>
      AudioReferenceLimits(
        maxCount: overrides._maxCount ?? _maxCount,
        mimeTypes: overrides._mimeTypes ?? _mimeTypes,
        maxBytes: overrides._maxBytes ?? _maxBytes,
        maxDurationMs: overrides._maxDurationMs ?? _maxDurationMs,
      );
}

class AudioModelCapabilities {
  const AudioModelCapabilities({
    int? maxPromptCharacters,
    Map<String, AudioReferenceLimits?>? references,
    bool? allowsMixedReferences,
    ConfigValue<int>? maxOutputDurationMs,
    bool? supportsAudioReferencePlaceholders,
  }) : _maxPromptCharacters = maxPromptCharacters,
       _references = references,
       _allowsMixedReferences = allowsMixedReferences,
       _maxOutputDurationMs = maxOutputDurationMs,
       _supportsAudioReferencePlaceholders = supportsAudioReferencePlaceholders;

  final int? _maxPromptCharacters;
  int get maxPromptCharacters => _maxPromptCharacters ?? 0;

  /// 覆盖层中值为 null 的类型表示该渠道不接受这种参考素材。
  final Map<String, AudioReferenceLimits?>? _references;
  Map<String, AudioReferenceLimits> get references => {
    for (final MapEntry(:key, :value) in (_references ?? const {}).entries)
      key: ?value,
  };
  final bool? _allowsMixedReferences;
  bool get allowsMixedReferences => _allowsMixedReferences ?? false;
  final ConfigValue<int>? _maxOutputDurationMs;
  int? get maxOutputDurationMs => _maxOutputDurationMs?.value;
  final bool? _supportsAudioReferencePlaceholders;
  bool get supportsAudioReferencePlaceholders =>
      _supportsAudioReferencePlaceholders ?? false;

  AudioModelCapabilities merge(
    AudioModelCapabilities overrides,
  ) => AudioModelCapabilities(
    maxPromptCharacters: overrides._maxPromptCharacters ?? _maxPromptCharacters,
    references: mergeModelReferences(
      _references,
      overrides._references,
      (base, override) => base.merge(override),
    ),
    allowsMixedReferences:
        overrides._allowsMixedReferences ?? _allowsMixedReferences,
    maxOutputDurationMs: overrides._maxOutputDurationMs ?? _maxOutputDurationMs,
    supportsAudioReferencePlaceholders:
        overrides._supportsAudioReferencePlaceholders ??
        _supportsAudioReferencePlaceholders,
  );
}

class AudioRequestDefaults {
  const AudioRequestDefaults({
    ConfigValue<String>? responseFormat,
    ConfigValue<int>? sampleRate,
    ConfigValue<int>? bitrate,
  }) : _responseFormat = responseFormat,
       _sampleRate = sampleRate,
       _bitrate = bitrate;

  final ConfigValue<String>? _responseFormat;
  String? get responseFormat => _responseFormat?.value;
  final ConfigValue<int>? _sampleRate;
  int? get sampleRate => _sampleRate?.value;
  final ConfigValue<int>? _bitrate;
  int? get bitrate => _bitrate?.value;

  AudioRequestDefaults merge(AudioRequestDefaults overrides) =>
      AudioRequestDefaults(
        responseFormat: overrides._responseFormat ?? _responseFormat,
        sampleRate: overrides._sampleRate ?? _sampleRate,
        bitrate: overrides._bitrate ?? _bitrate,
      );

  Map<String, dynamic> toJson() => {
    if (_responseFormat != null) 'response_format': responseFormat,
    if (_sampleRate != null) 'sample_rate': sampleRate,
    if (_bitrate != null) 'bitrate': bitrate,
  };

  factory AudioRequestDefaults.fromJson(Map<String, dynamic> json) =>
      AudioRequestDefaults(
        responseFormat: json.containsKey('response_format')
            ? ConfigValue(json['response_format'] as String?)
            : null,
        sampleRate: json.containsKey('sample_rate')
            ? ConfigValue(json['sample_rate'] as int?)
            : null,
        bitrate: json.containsKey('bitrate')
            ? ConfigValue(json['bitrate'] as int?)
            : null,
      );
}
