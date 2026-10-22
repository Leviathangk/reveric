// 职责: 桌面端设置对话框 — 渲染存储空间、变更记录保留和备份设置入口。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/desktop/widgets/settings/storage_panel.dart
// 遵循的 Rules:
//   .agents/rules/directory-structure.md
part of 'settings_dialog.dart';

class _StorageSettingsSection extends StatelessWidget {
  const _StorageSettingsSection();

  @override
  Widget build(BuildContext context) {
    return const StoragePanel();
  }
}
