// 职责: 通过 Gemini generateContent 接口文生图并解析内联图片回执。
// 关联文件:
//   lib/shared/services/ai/image/client.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;

import '../../../models/ai_provider.dart';
import '../../../localization/locale_keys.dart';
import '../image.dart';
import 'client.dart';

class GeminiImageClient extends ImageClient {
  GeminiImageClient(super.config);

  @override
  bool get supportsEdit => false;

  @override
  Future<AiImageGenerationResult> generate(
    ImageGenerationRequest request,
  ) async {
    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/${request.model}:generateContent?key=${config.effectiveApiKey}',
    );
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': request.prompt},
          ],
        },
      ],
      'generationConfig': {
        'responseModalities': ['IMAGE', 'TEXT'],
      },
    });

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw AiImageGenerationException(
        'Gemini 图片生成失败 (${response.statusCode})',
        debugMessage: response.body,
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImageNoResult));
    }
    final parts =
        (candidates[0] as Map<String, dynamic>)['content']?['parts'] as List? ??
        [];

    String? base64Data;
    String? mimeType;
    for (final part in parts) {
      if (part is Map && part['inlineData'] is Map) {
        final inlineData = part['inlineData'] as Map;
        base64Data = inlineData['data'] as String?;
        mimeType = inlineData['mimeType'] as String?;
        break;
      }
    }

    if (base64Data == null) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImageNoResult));
    }

    final localPath = await saveImageBase64(base64Data);
    return AiImageGenerationResult(
      imageBase64: base64Data,
      localFilePath: localPath,
      mimeSubtype: _mimeSubtypeFromType(mimeType),
    );
  }

  String _mimeSubtypeFromType(String? mimeType) {
    if (mimeType == null) return 'png';
    if (mimeType.contains('jpeg') || mimeType.contains('jpg')) return 'jpeg';
    if (mimeType.contains('webp')) return 'webp';
    if (mimeType.contains('gif')) return 'gif';
    return 'png';
  }
}
