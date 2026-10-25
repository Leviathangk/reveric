// 职责: 保存音频响应与临时下载地址，并统一响应格式对应的本地文件格式。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/services/production/audio_service.dart
import 'dart:typed_data';
import 'exception.dart';

class AudioGenerationResult {
  AudioGenerationResult(Uint8List bytes, {this.url, this.providerTaskId})
    : bytes = Uint8List.fromList(bytes);
  AudioGenerationResult.pending(String id)
    : providerTaskId = id,
      bytes = Uint8List(0),
      url = null;
  final Uint8List bytes;
  final Uri? url;
  final String? providerTaskId;
  bool get isPending => providerTaskId != null && url == null && bytes.isEmpty;
}

/// Raw PCM is wrapped in WAV by the response adapter without re-encoding.
String audioOutputFileFormat(String? responseFormat) =>
    switch (responseFormat) {
      'pcm' || 'wav' => 'wav',
      'mp3' => 'mp3',
      _ => throw const AudioException('invalid_config'),
    };
