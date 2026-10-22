// 职责: 验证音频历史冻结的参考文件与输出回执随作品备份保留。
// 关联文件:
//   lib/shared/services/production/backup_media.dart
//   test/helpers/backup_fixture.dart
import 'dart:convert';
import 'package:reveric/shared/models/audio/request.dart';
import 'package:reveric/shared/models/generation/task.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/backup_fixture.dart';
import 'package:reveric/shared/services/production/backup_media.dart';

void main() {
  test(
    'audio history keeps frozen reference files and output receipt in selected backups',
    () async {
      final dir = await Directory.systemTemp.createTemp('audio-backup-');
      final schemas = await BackupDatabases.create();
      final db = schemas.writeMain('${dir.path}/reveric.sqlite');
      insertBackupRow(db, 'assets', {
        'id': 'original',
        'type': 'audio',
        'purpose': 'reference',
        'path': 'file_workspaces/work/audio/original.wav',
      });
      final request = AudioGenerationRequest(
        AudioRequest(
          providerId: 'p',
          modelId: 'seed-audio-1.0',
          prompt: '@Audio1',
          originalPrompt: 'voice',
          references: [
            const AudioReference(
              assetId: 'original',
              kind: 'audio',
              mimeType: 'audio/wav',
              bytes: 44,
              durationMs: 1000,
            ),
          ],
        ),
      );
      insertBackupRow(db, 'generation_tasks', {
        'id': 'task',
        'kind': 'audio',
        'novel_id': 'work',
        'source_type': 'production_clip',
        'source_id': 'clip',
        'provider_id': 'p',
        'provider_type': 'test',
        'model_id': 'seed-audio-1.0',
        'status': 'completed',
        'request_json': jsonEncode(request.toJson()),
        'path': 'file_workspaces/work/audio/generated.wav',
        'output_url': 'https://output.example/generated.wav',
      });
      db.close();
      try {
        final backup = collectSelectedMedia(
          backup: dir,
          novelIds: {'work'},
          contentPaths: [],
        );
        expect(
          backup.rows['assets']!.map((row) => row['id']),
          contains('original'),
        );
        expect(
          backup.rows['generation_tasks']!.single['output_url'],
          'https://output.example/generated.wav',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
}
