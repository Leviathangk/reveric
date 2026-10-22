// 职责: 存储设置区 — 展示对象存储说明并承载连接表单（仅桌面设置对话框使用）。
// 关联文件:
//   lib/shared/widgets/settings/object_storage_form.dart
//   lib/shared/providers/object_storage.dart
//   lib/desktop/widgets/settings/settings_object_storage_section.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/object_storage.dart';
import '../../theme/theme.dart';
import 'object_storage_form.dart';

class ObjectStorageSettingsSection extends ConsumerWidget {
  const ObjectStorageSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final config = ref.watch(objectStorageConfigProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.settingsStorage),
            style: typo.heading2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.settingsStorageDescription),
            style: typo.body.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          // 配置读完前不显示可编辑表单，避免用默认值覆盖已保存配置。
          if (config.asData?.value case final config?)
            ObjectStorageForm(config: config),
        ],
      ),
    );
  }
}
