// 职责: 测试 Write 工具写入 characters.avatar_path（设为头像 / 清除）。
// 关联文件:
//   lib/shared/services/ai/tools_write.dart
//   lib/shared/utils/storage_paths.dart
//   lib/shared/services/novel_content.dart

import 'dart:convert';
import 'package:reveric/shared/models/asset_purpose.dart';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';
import 'package:reveric/shared/services/ai/tools.dart';
import 'package:reveric/shared/services/novel_actions.dart';
import 'package:reveric/shared/services/image_library_service.dart';
import 'package:reveric/shared/services/novel_content.dart';
import 'package:reveric/shared/services/working_overlay.dart';
import 'package:reveric/shared/utils/storage_paths.dart';
import 'package:path/path.dart' as p;

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);

void main() {
  group('Write character avatar_path', () {
    late Directory tempSupport;
    late _AvatarTestDatabase db;
    late AppDatabase appDb;
    late _AvatarTestContentService contentService;
    late AiToolManager toolManager;
    late _AvatarTestOverlay overlay;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempSupport = await Directory.systemTemp.createTemp(
        'reveric_write_avatar_',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async {
              if (call.method == 'getApplicationSupportDirectory') {
                return tempSupport.path;
              }
              throw StateError('image_save_failed');
            },
          );
      await RevericPaths.initialize();

      db = _AvatarTestDatabase();
      appDb = AppDatabase.forTest(NativeDatabase.memory());
      contentService = _AvatarTestContentService(
        db,
        imageLibraryService: buildImageLibraryService(appDb),
      );

      toolManager = AiToolManager(
        contentService,
        workingOverlayService: overlay = _AvatarTestOverlay(
          db,
          contentService,
          novelActionsService: NovelActionsService(appDb),
        ),
      )..registerAllTools();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      await db.close();
      await appDb.close();
      if (await tempSupport.exists()) {
        await tempSupport.delete(recursive: true);
      }
    });

    test(
      'photo Write preserves asset IDs for rollback and clearing never deletes files',
      () async {
        final file = File(p.join(tempSupport.path, 'images', 'photo.png'));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(_png);
        final id = await contentService.createCharacterProfile(name: 'Subject');
        final stored = (await buildImageLibraryService(appDb).importFile(
          file.path,
          novelId: 'novel_test',
          purpose: AssetPurpose.photo,
        )).id;
        await contentService.updateCharacterAvatarAndPhotos(
          entryId: id,
          photos: [SubjectPhoto(assetId: stored, name: 'Original')],
        );
        final result = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'characters/$id/photos',
            'value': [
              {'name': '冬装', 'asset_id': stored},
            ],
          },
        );
        expect(result['updated'], isTrue);
        expect((await contentService.getCharacterProfileById(id))!.photos, [
          SubjectPhoto(assetId: stored, name: '冬装'),
        ]);
        final change = (await db.workingChangeDao.getByResource(
          'characters/$id/photos',
        )).single;
        expect(
          await overlay.rejectWorkingChange(change.id),
          RollbackChangeResult.rolledBack,
        );
        expect((await contentService.getCharacterProfileById(id))!.photos, [
          SubjectPhoto(assetId: stored, name: 'Original'),
        ]);
        final clear = await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'characters/$id/photos', 'value': []},
        );
        expect(clear['updated'], isTrue);
        expect(
          (await contentService.getCharacterProfileById(id))!.photos,
          isEmpty,
        );
        expect(await file.readAsBytes(), _png);
      },
    );

    test(
      'invalid chapter rejects all fields before importing an avatar',
      () async {
        final id = await contentService.createCharacterProfile(
          name: '原名',
          tags: ['原标签'],
        );
        final before = (await contentService.getCharacterProfileById(id))!;
        final source = File(p.join(tempSupport.path, 'source.png'));
        await source.writeAsBytes(_png);
        for (final chapter in [
          'ch_missing',
          await contentService.createVolume(title: '卷'),
        ]) {
          final result = await toolManager.executeTool(
            name: 'Write',
            input: {
              'path': 'characters/$id',
              'fields': {
                'avatar_path': source.path,
                'tags': ['新标签'],
                'biography': '新传记',
                'first_appear_chapter_id': chapter,
              },
            },
          );
          expect(result['error_code'], 'invalid_argument');
          expect(
            (await contentService.getCharacterProfileById(id))!.toJson(),
            before.toJson(),
          );
          expect(contentService.imageSaveCount, 0);
          expect(await db.select(db.workingChanges).get(), isEmpty);
        }
        expect(await source.exists(), isTrue);
      },
    );

    test(
      'later staging failure rolls back avatar tags text and history and retains registered assets',
      () async {
        final id = await contentService.createCharacterProfile(
          name: '原名',
          tags: ['原标签'],
        );
        final source = File(p.join(tempSupport.path, 'source.png'));
        await source.writeAsBytes(_png);
        await toolManager.executeTool(
          name: 'Write',
          input: {'path': 'characters/$id/avatar_path', 'value': source.path},
        );
        final before = (await contentService.getCharacterProfileById(id))!;
        final original = RevericPaths.resolveStored(
          await contentService.imagePath(before.avatarAssetId),
        )!;
        final filesBefore = tempSupport
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path)
            .toSet();
        overlay.failOnSecondChange = true;
        await expectLater(
          toolManager.executeTool(
            name: 'Write',
            input: {
              'path': 'characters/$id',
              'fields': {
                'avatar_path': source.path,
                'tags': ['新标签'],
                'biography': '新传记',
                'personality': '新性格',
              },
            },
          ),
          throwsStateError,
        );
        expect(overlay.completedChanges, 2);
        expect(
          (await contentService.getCharacterProfileById(id))!.toJson(),
          before.toJson(),
        );
        expect(await db.select(db.workingChanges).get(), isEmpty);
        expect(await db.select(db.changeCommits).get(), isEmpty);
        expect(await File(original).exists(), isTrue);
        expect(await source.exists(), isTrue);
        expect(
          tempSupport
              .listSync(recursive: true)
              .whereType<File>()
              .map((f) => f.path)
              .toSet(),
          filesBefore,
        );
        expect(contentService.imageSaveCount, 2);
        expect(contentService.savedInsideTransaction, isFalse);
        overlay.failOnSecondChange = false;
        final success = await toolManager.executeTool(
          name: 'Write',
          input: {
            'path': 'characters/$id',
            'fields': {
              'avatar_path': source.path,
              'tags': ['新标签'],
              'biography': '新传记',
              'personality': '新性格',
            },
          },
        );
        expect(success['error'], isNull, reason: '$success');
        final after = (await contentService.getCharacterProfileById(id))!;
        expect(after.tags, ['新标签']);
        expect(after.biography, '新传记');
        expect(after.personality, '新性格');
        expect(after.avatarAssetId, before.avatarAssetId);
        expect(await db.select(db.workingChanges).get(), hasLength(2));
        expect(contentService.savedInsideTransaction, isFalse);
      },
    );

    test(
      'rollback preserves a deduplicated image library asset and source file',
      () async {
        final source = File(p.join(tempSupport.path, 'shared.png'));
        await source.writeAsBytes(_png);
        final library = buildImageLibraryService(appDb);
        final asset = await library.importFile(
          source.path,
          novelId: 'novel_test',
          purpose: AssetPurpose.avatar,
        );
        final service = _AvatarTestContentService(
          db,
          imageLibraryService: library,
        );
        final id = await service.createCharacterProfile(name: '原名');
        final before = (await service.getCharacterProfileById(id))!.toJson();
        final tools = AiToolManager(service, workingOverlayService: overlay)
          ..registerAllTools();
        addTearDown(tools.dispose);
        overlay.failOnSecondChange = true;
        await expectLater(
          tools.executeTool(
            name: 'Write',
            input: {
              'path': 'characters/$id',
              'fields': {
                'avatar_path': source.path,
                'tags': ['新标签'],
                'biography': '传记',
                'personality': '性格',
              },
            },
          ),
          throwsStateError,
        );
        expect((await service.getCharacterProfileById(id))!.toJson(), before);
        expect(await db.select(db.workingChanges).get(), isEmpty);
        final restoredAsset = (await appDb.imageAssetDao.getAsset(asset.id))!;
        expect(
          {
            ...restoredAsset.toJson(),
            'content': restoredAsset.content?.toJson(),
          },
          {...asset.toJson(), 'content': asset.content?.toJson()},
        );
        expect(
          await File(RevericPaths.resolveStored(asset.path)!).exists(),
          isTrue,
        );
        expect(await source.exists(), isTrue);
        expect(service.savedInsideTransaction, isFalse);
      },
    );

    // 模型生成头像后显式 Write avatar_path，应拷贝到小说 images/ 并写入角色。
    test('sets avatar from a local image path', () async {
      final characterId = await contentService.createCharacterProfile(
        defaultName: '测试角色',
      );
      final source = File(p.join(tempSupport.path, 'gen_avatar.png'));
      await source.writeAsBytes(_png);

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'characters/$characterId/avatar_path',
          'value': source.path,
        },
        callId: 'call_write_avatar_set',
      );

      expect(result['error'], isNull);
      expect(result['updated'], isTrue);
      expect(result['fields'], contains('avatar_path'));
      final stored = result['avatar_path'] as String;
      expect(stored, isNotEmpty);
      expect(RevericPaths.resolveStored(stored), isNotNull);

      final profile = await contentService.getCharacterProfileById(characterId);
      expect(await contentService.imagePath(profile?.avatarAssetId), stored);
    });

    test('clears avatar with empty string', () async {
      final characterId = await contentService.createCharacterProfile(
        defaultName: '清空头像',
      );
      final source = File(p.join(tempSupport.path, 'to_clear.png'));
      await source.writeAsBytes(_png);
      await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'characters/$characterId/avatar_path',
          'value': source.path,
        },
        callId: 'call_write_avatar_before_clear',
      );

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {'path': 'characters/$characterId/avatar_path', 'value': ''},
        callId: 'call_write_avatar_clear',
      );

      expect(result['error'], isNull);
      expect(result['updated'], isTrue);
      expect(result['avatar_path'], isNull);
      final profile = await contentService.getCharacterProfileById(characterId);
      expect(profile?.avatarAssetId, isNull);
    });

    test('returns file_not_found for missing image', () async {
      final characterId = await contentService.createCharacterProfile(
        defaultName: '缺失文件',
      );

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'characters/$characterId/avatar_path',
          'value': p.join(tempSupport.path, 'missing.png'),
        },
        callId: 'call_write_avatar_missing',
      );

      expect(result['updated'], isNot(isTrue));
      expect(result['error_code'], 'invalid_argument');
    });

    test('save_failed preserves the avatar without a working change', () async {
      final characterId = await contentService.createCharacterProfile(
        name: '保留旧头像',
      );
      final previous = File(p.join(tempSupport.path, 'previous.png'));
      await previous.writeAsBytes(_png);
      final stored = RevericPaths.toRelative(previous.path)!;
      await contentService.updateCharacterAvatarAndPhotos(
        entryId: characterId,
        avatarAssetId: stored,
        photos: [SubjectPhoto(assetId: stored, name: 'Original')],
      );
      final source = File(p.join(tempSupport.path, 'replacement.png'));
      await source.writeAsBytes(_png);
      contentService.failImageSave = true;

      final result = await toolManager.executeTool(
        name: 'Write',
        input: {
          'path': 'characters/$characterId/avatar_path',
          'value': source.path,
        },
      );

      expect(result['error_code'], 'internal');
      expect(result['updated'], isNot(isTrue));
      final character = await contentService.getCharacterProfileById(
        characterId,
      );
      expect(character!.avatarAssetId, stored);
      expect(character.photos, [
        SubjectPhoto(assetId: stored, name: 'Original'),
      ]);
      expect(await previous.exists(), isTrue);
      expect(await db.select(db.workingChanges).get(), isEmpty);
    });
  });
}

class _AvatarTestContentService extends NovelContentService {
  _AvatarTestContentService(super.database, {super.imageLibraryService});

  bool failImageSave = false;
  int imageSaveCount = 0;
  bool savedInsideTransaction = false;

  @override
  Future<String> requireNovelId() async => 'novel_test';

  @override
  Future<String> saveCharacterImage({
    required String sourcePath,
    required String kind,
  }) async {
    imageSaveCount++;
    savedInsideTransaction |=
        (database as _AvatarTestDatabase).transactionDepth > 0;
    if (failImageSave) {
      throw StateError('image_save_failed');
    }
    return super.saveCharacterImage(sourcePath: sourcePath, kind: kind);
  }
}

class _AvatarTestDatabase extends NovelContentDatabase {
  _AvatarTestDatabase() : super.forTest(NativeDatabase.memory());
  int transactionDepth = 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) async {
    transactionDepth++;
    try {
      return await super.transaction(action, requireNew: requireNew);
    } finally {
      transactionDepth--;
    }
  }
}

class _AvatarTestOverlay extends WorkingOverlayService {
  _AvatarTestOverlay(
    super.db,
    super.service, {
    required super.novelActionsService,
  });
  bool failOnSecondChange = false;
  int completedChanges = 0;

  @override
  Future<WorkingChange> stageTextChange({
    required String resourcePath,
    required String resourceType,
    required String? resourceId,
    required String? field,
    required String? oldText,
    required String newText,
    required String source,
    String? sourceSessionId,
    String? sourceTurnId,
    String? toolName,
    String? summary,
    String? expectedCurrentText,
    bool restoreHistory = false,
  }) async {
    final result = await super.stageTextChange(
      resourcePath: resourcePath,
      resourceType: resourceType,
      resourceId: resourceId,
      field: field,
      oldText: oldText,
      newText: newText,
      source: source,
      sourceSessionId: sourceSessionId,
      sourceTurnId: sourceTurnId,
      toolName: toolName,
      summary: summary,
      expectedCurrentText: expectedCurrentText,
      restoreHistory: restoreHistory,
    );
    completedChanges++;
    if (failOnSecondChange && completedChanges == 2) {
      throw StateError(
        'Injected failure after staging the second character field',
      );
    }
    return result;
  }
}
