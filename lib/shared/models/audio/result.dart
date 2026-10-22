// 职责: 保存音频响应与临时下载地址，并统一响应格式对应的本地文件格式。
// 关联文件:
//   lib/shared/services/ai/audio/client.dart
//   lib/shared/services/production/audio_service.dart
import 'dart:typed_data';
import 'exception.dart';

class AudioGenerationResult {
  AudioGenerationResult(Uint8List bytes, {this.url})
    : bytes = Uint8List.fromList(bytes);
  final Uint8List bytes;
  final Uri? url;
}

/// Raw PCM is wrapped in WAV by the response adapter without re-encoding.
String audioOutputFileFormat(String? responseFormat) =>
    switch (responseFormat) {
      'pcm' || 'wav' => 'wav',
      'mp3' => 'mp3',
      _ => throw const AudioException('invalid_config'),
    };
