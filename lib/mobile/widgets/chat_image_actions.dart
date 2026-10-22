// 职责: 移动端聊天里把 AI 生成的图片应用到角色头像或角色 / 物品照片，失败时提示保存失败。
// 关联文件:
//   lib/shared/widgets/ai/chat/chat_message_view.dart
//   lib/shared/services/novel_content.dart
//   lib/shared/services/item_photo_import_orchestrator.dart
//   lib/mobile/pages/novel_chat_page.dart
//   lib/mobile/pages/chat_session_page.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/file-access.md
//   .agents/rules/error-handling.md
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/models/subject_photo.dart';
import '../../shared/providers/novel_providers.dart';
import '../../shared/services/item_photo_import_orchestrator.dart';

final _log = AppLogger.forModule('MobileChatImageActions');

Future<void> setGeneratedImageAsAvatar(
  BuildContext context,
  WidgetRef ref, {
  required String databasePath,
  required String localPath,
  required String characterId,
}) => _apply(context, () async {
  final service = ref.read(novelContentServiceProvider(databasePath));
  final assetId = await service.saveCharacterImage(
    sourcePath: localPath,
    kind: 'avatar',
  );
  await service.updateCharacterAvatarAndPhotos(
    entryId: characterId,
    avatarAssetId: assetId,
  );
});

Future<void> addGeneratedImageAsPhoto(
  BuildContext context,
  WidgetRef ref, {
  required String databasePath,
  required String localPath,
  String? characterId,
  String? itemId,
}) => _apply(context, () async {
  final service = ref.read(novelContentServiceProvider(databasePath));
  if (characterId != null && characterId.isNotEmpty) {
    final assetId = await service.saveCharacterImage(
      sourcePath: localPath,
      kind: 'photo',
    );
    final existing =
        (await service.getCharacterProfileById(characterId))?.photos ??
        const <SubjectPhoto>[];
    await service.updateCharacterAvatarAndPhotos(
      entryId: characterId,
      photos: [
        ...existing,
        SubjectPhoto(assetId: assetId),
      ],
    );
  } else if (itemId != null && itemId.isNotEmpty) {
    await ItemPhotoImportOrchestrator().import(
      content: service,
      library: ref.read(imageLibraryServiceProvider),
      itemId: itemId,
      paths: [localPath],
    );
  }
});

Future<void> _apply(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error, stackTrace) {
    _log.error(
      'Apply generated image failed',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t(LocaleKeys.commonSaveFailed))),
      );
    }
  }
}
