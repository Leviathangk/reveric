// 职责: 桌面端设置对话框 — 渲染对象存储连接设置。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/object_storage_settings_section.dart
// 遵循的 Rules:
//   .agents/rules/directory-structure.md
part of 'settings_dialog.dart';

class _ObjectStorageSettingsSection extends StatelessWidget {
  const _ObjectStorageSettingsSection();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Scaffold(
      backgroundColor: colors.canvas,
      body: const ObjectStorageSettingsSection(),
    );
  }
}
