// 职责: 验证初始化数据库保留作品数据能力且不再创建已移除功能的表。
// 关联文件:
//   lib/shared/database/app_database.dart
//   lib/shared/database/app_database_indexes.dart
//   lib/shared/database/novel_content_database.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/database/app_database.dart';
import 'package:reveric/shared/database/novel_content_database.dart';

void main() {
  test('fresh schema excludes removed feature tables', () async {
    final database = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(database.close);
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = tables.map((row) => row.read<String>('name')).toSet();
    expect(
      names,
      containsAll([
        'novels',
        'ai_chat_sessions',
        'generation_tasks',
        'provider_assets',
        'todos',
        'assets',
        'ai_usages',
      ]),
    );
    for (final removed in [
      'ai_credit_usages',
      'craft_assets',
      'tasks',
      'tips',
      'focus_periods',
      'humanize_history_entries',
      'breakdown_runs',
      'breakdown_run_items',
      'artifact_shares',
    ]) {
      expect(names, isNot(contains(removed)));
    }
    final usageColumns = await database
        .customSelect('PRAGMA table_info(ai_usages)')
        .get();
    final usageNames = usageColumns.map((row) => row.read<String>('name'));
    expect(usageNames, containsAll(['input_tokens', 'output_tokens']));
    expect(usageNames, isNot(contains('credits')));
    expect(usageNames, isNot(contains('pricing_rate_id')));
    final providerColumns = await database
        .customSelect('PRAGMA table_info(ai_providers)')
        .get();
    for (final name in [
      'access_key_id',
      'secret_access_key',
      'asset_project_name',
    ]) {
      final column = providerColumns.singleWhere(
        (row) => row.read<String>('name') == name,
      );
      expect(column.read<String>('type'), 'TEXT');
      expect(column.read<int>('notnull'), 0);
    }
    final certificationIndexes = await database
        .customSelect('PRAGMA index_list(provider_assets)')
        .get();
    expect(
      certificationIndexes.map((row) => row.read<String>('name')),
      containsAll([
        'provider_assets_by_asset_id_provider_id',
        'provider_assets_by_status',
      ]),
    );
    await database.novelDao.create(
      id: 'novel',
      title: 'Novel',
      description: '',
    );
    expect(
      (await database.select(database.novels).get()).single.title,
      'Novel',
    );
  });

  test(
    'content schema keeps writing tables without analysis results',
    () async {
      final database = NovelContentDatabase.forTest(NativeDatabase.memory());
      addTearDown(database.close);
      final tables = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .get();
      final names = tables.map((row) => row.read<String>('name')).toSet();
      expect(
        names,
        containsAll(['chapter_nodes', 'documents', 'character_profiles']),
      );
      for (final removed in [
        'breakdown_chapters',
        'breakdown_reports',
        'breakdown_documents',
        'breakdown_characters',
      ]) {
        expect(names, isNot(contains(removed)));
      }
    },
  );
  test('fresh schemas contain current business columns only', () async {
    final app = AppDatabase.forTest(NativeDatabase.memory());
    final content = NovelContentDatabase.forTest(NativeDatabase.memory());
    addTearDown(app.close);
    addTearDown(content.close);
    for (final (table, removed) in [
      ('novels', 'ai_settings'),
      ('ai_providers', 'max_tokens'),
    ]) {
      final columns = await app.customSelect('PRAGMA table_info($table)').get();
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains(removed)),
      );
    }
    for (final table in ['screenplay_episodes', 'screenplay_scenes']) {
      final columns = await content
          .customSelect('PRAGMA table_info($table)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains('target_duration_seconds')),
      );
      expect(
        columns.map((row) => row.read<String>('name')),
        isNot(contains('estimated_duration_seconds')),
      );
    }
    final characterColumns = await content
        .customSelect('PRAGMA table_info(character_profiles)')
        .get();
    final names = characterColumns.map((row) => row.read<String>('name'));
    expect(names, contains('biography'));
    expect(names, isNot(contains('summary')));
    await content
        .into(content.characterProfiles)
        .insert(
          CharacterProfilesCompanion.insert(id: 'character', name: 'Character'),
        );
    expect(
      (await content.select(content.characterProfiles).getSingle()).biography,
      '',
    );
  });
}
