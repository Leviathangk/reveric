// 职责: 验证紧凑日志的信息保留、文件初始化与启动前归档阈值行为
// 关联文件:
//   lib/shared/logger/log_manager.dart
//   lib/shared/logger/compact_printer.dart
// 遵循的 Rules:
//   .agents/rules/directory-structure.md
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:reveric/shared/logger/compact_printer.dart';
import 'package:reveric/shared/logger/log_manager.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CompactLogPrinter', () {
    test('writes normal events on one line with time, level and module', () {
      final time = DateTime.utc(2026, 9, 24, 12, 34, 56);
      final lines = CompactLogPrinter().log(
        LogEvent(Level.info, '[Agent] request completed', time: time),
      );

      expect(lines, [
        '2026-09-24T12:34:56.000Z [INFO] [Agent] request completed',
      ]);
    });

    test('preserves multiline errors and every supplied stack frame', () {
      const message = '[Agent] request failed\nprovider response detail';
      final error = StateError('upstream failed\nresponse body');
      final stack = List.generate(
        12,
        (index) => '#$index caller$index (package:example/app.dart:$index:1)',
      ).join('\n');
      final lines = CompactLogPrinter().log(
        LogEvent(
          Level.error,
          message,
          error: error,
          stackTrace: StackTrace.fromString(stack),
        ),
      );

      expect(lines.first, endsWith('[ERROR] $message'));
      expect(lines[1], 'Error: $error');
      expect(lines[2], stack);
    });
  });

  group('LogManager.prepareLatestLogFile', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('reveric_log_test_');
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('keeps latest.log when it is at or below the size limit', () async {
      final latestLog = File(p.join(tempDir.path, 'latest.log'));
      await latestLog.writeAsBytes(List.filled(16, 65));

      await LogManager.prepareLatestLogFile(
        tempDir.path,
        maxLatestLogSizeBytes: 16,
      );

      expect(latestLog.existsSync(), isTrue);
      expect(await latestLog.length(), 16);
      expect(await _startupLogFiles(tempDir), isEmpty);
    });

    test('archives latest.log only after it exceeds the size limit', () async {
      final latestLog = File(p.join(tempDir.path, 'latest.log'));
      await latestLog.writeAsBytes(List.filled(17, 65));

      await LogManager.prepareLatestLogFile(
        tempDir.path,
        maxLatestLogSizeBytes: 16,
      );

      expect(latestLog.existsSync(), isTrue);
      expect(await latestLog.length(), 0);

      final startupLogs = await _startupLogFiles(tempDir);
      expect(startupLogs, hasLength(1));
      expect(await startupLogs.single.length(), 17);
    });

    test('appendCheckpointSync persists a checkpoint immediately', () {
      final file = File(p.join(tempDir.path, 'latest.log'));

      LogManager.appendCheckpointSync(
        file.path,
        'native call started',
        timestamp: DateTime.utc(2026, 8, 6, 12),
      );

      final content = file.readAsStringSync();
      expect(content, contains('2026-08-06T12:00:00.000Z'));
      expect(content, contains('[Checkpoint] native call started'));
    });
  });
}

Future<List<File>> _startupLogFiles(Directory directory) async {
  return directory
      .listSync()
      .whereType<File>()
      .where((file) => p.basename(file.path).startsWith('startup_'))
      .toList();
}
