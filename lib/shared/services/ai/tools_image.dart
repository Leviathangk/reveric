// 职责: AI 图片生成 handler — GenerateAvatar/GeneratePhoto 的处理逻辑（slash 命令 / UI 按钮驱动）。
// 关联文件:
//   lib/shared/agent/tools.dart
//   lib/shared/services/ai/image.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
part of 'tools.dart';

const _avatarImageSize = '1024x1024';
const _photoImageSize = '864x1536';

mixin _AiToolManagerImageMixin on _AiToolManagerBase {
  Future<Map<String, dynamic>> _handleGenerateAvatar(
    Map<String, dynamic> input,
  ) async {
    if (imageGenerationCallback == null) {
      return {
        'success': false,
        'error': tr(LocaleKeys.aiNoImageModelConfigured),
        '_noImageModel': true,
        'error_code': ToolErrorCode.unavailable.name,
      };
    }
    final prompt = _parseStringArgument(input['prompt']);
    if (prompt.isEmpty) {
      return {
        'success': false,
        'error': tr(LocaleKeys.aiImagePromptEmpty),
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }
    final characterId = _parseStringArgument(input['character_id']);
    final imagePath = _parseStringArgument(input['path'], trim: true);
    try {
      final result = imagePath.isNotEmpty
          ? await _handleGenerateAvatarFromSource(prompt, imagePath: imagePath)
          : await imageGenerationCallback!(prompt, size: _avatarImageSize);
      return {
        'success': true,
        'local_path':
            RevericPaths.toRelative(result.localFilePath) ??
            result.localFilePath!,
        'character_id': characterId,
      };
    } catch (e) {
      final errorMessage = switch (e) {
        AiImageGenerationException(:final userMessage) => userMessage,
        _ => tr(LocaleKeys.aiAvatarGenRetry),
      };
      return {
        'success': false,
        'error': errorMessage,
        'error_code': ToolErrorCode.internal.name,
      };
    }
  }

  Future<AiImageGenerationResult> _handleGenerateAvatarFromSource(
    String prompt, {
    required String imagePath,
  }) async {
    if (imageEditCallback == null) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImageEditUnavailable));
    }
    if (imagePath.isEmpty) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImagePathEmpty));
    }
    return imageEditCallback!(prompt, imageData: imagePath);
  }

  Future<Map<String, dynamic>> _handleGeneratePhoto(
    Map<String, dynamic> input,
  ) async {
    if (imageGenerationCallback == null) {
      return {
        'success': false,
        'error': tr(LocaleKeys.aiNoImageModelConfigured),
        '_noImageModel': true,
        'error_code': ToolErrorCode.unavailable.name,
      };
    }
    final prompt = _parseStringArgument(input['prompt']);
    if (prompt.isEmpty) {
      return {
        'success': false,
        'error': tr(LocaleKeys.aiImagePromptEmpty),
        'error_code': ToolErrorCode.invalid_argument.name,
      };
    }
    final characterId = _parseStringArgument(input['character_id']);
    final itemId = _parseStringArgument(input['item_id']);
    final imagePath = _parseStringArgument(input['path'], trim: true);
    try {
      final result = imagePath.isNotEmpty
          ? await _handleGeneratePhotoFromSource(prompt, imagePath: imagePath)
          : await imageGenerationCallback!(prompt, size: _photoImageSize);
      return {
        'success': true,
        'local_path':
            RevericPaths.toRelative(result.localFilePath) ??
            result.localFilePath!,
        if (characterId.isNotEmpty) 'character_id': characterId,
        if (itemId.isNotEmpty) 'item_id': itemId,
      };
    } catch (e) {
      final errorMessage = switch (e) {
        AiImageGenerationException(:final userMessage) => userMessage,
        _ => tr(LocaleKeys.aiPhotoGenRetry),
      };
      return {
        'success': false,
        'error': errorMessage,
        'error_code': ToolErrorCode.internal.name,
      };
    }
  }

  Future<AiImageGenerationResult> _handleGeneratePhotoFromSource(
    String prompt, {
    required String imagePath,
  }) async {
    if (imageEditCallback == null) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImageEditUnavailable));
    }
    if (imagePath.isEmpty) {
      throw AiImageGenerationException(tr(LocaleKeys.aiImagePathEmpty));
    }
    return imageEditCallback!(prompt, imageData: imagePath);
  }
}
