// 职责: 桌面端设置对话框存储页 — 提供 Scaffold 壳并承载共享存储设置区。
// 关联文件:
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/storage_settings_section.dart
//   lib/shared/theme/theme.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';

import '../../../shared/theme/theme.dart';
import '../../../shared/widgets/settings/storage_settings_section.dart';

/// Storage 配置面板外壳。
class StoragePanel extends StatelessWidget {
  const StoragePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: const StorageSettingsSection(),
    );
  }
}
