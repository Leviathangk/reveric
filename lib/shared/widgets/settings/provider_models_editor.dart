// 职责: 统一供应商模型列表的手动添加、删除与获取入口，并持有本地输入状态。
// 关联文件:
//   lib/shared/widgets/settings/provider_config_panel.dart
//   lib/shared/widgets/settings/provider_video_models.dart
//   lib/shared/widgets/settings/provider_audio_models.dart
//   lib/shared/components/reveric_inputs.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../components/reveric_icon_button.dart';
import '../../components/reveric_inputs.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

class ProviderModelsEditor extends HookWidget {
  const ProviderModelsEditor({
    super.key,
    required this.label,
    required this.hint,
    required this.models,
    required this.onChanged,
    this.fetchButton,
  });

  final String label;
  final String hint;
  final List<String> models;
  final ValueChanged<List<String>> onChanged;
  final Widget? fetchButton;

  @override
  Widget build(BuildContext context) {
    final inputController = useTextEditingController();
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    void addModel() {
      final next = inputController.text.trim();
      if (next.isEmpty || models.contains(next)) {
        return;
      }
      onChanged([...models, next]);
      inputController.clear();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),
            ?fetchButton,
          ],
        ),
        const SizedBox(height: RevericSpacing.xs),
        Container(
          padding: const EdgeInsets.all(RevericSpacing.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.medium),
            border: Border.all(color: colors.borderInput),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (models.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: RevericSpacing.sm),
                  child: Text(
                    context.t(LocaleKeys.settingsProviderNoModelsYet),
                    style: typo.uiSmall.copyWith(color: colors.textMuted),
                  ),
                ),
              for (final model in models) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: RevericSpacing.xs),
                  padding: const EdgeInsets.symmetric(
                    horizontal: RevericSpacing.sm,
                    vertical: RevericSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainer,
                    borderRadius: BorderRadius.circular(RevericRadius.medium),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          model,
                          style: typo.ui.copyWith(color: colors.textPrimary),
                        ),
                      ),
                      RevericIconButton(
                        onPressed: () => onChanged(
                          models.where((item) => item != model).toList(),
                        ),
                        icon: RevericIcons.close,
                        tooltip: context.t(LocaleKeys.commonDelete),
                      ),
                    ],
                  ),
                ),
              ],
              RevericInlineActionInput(
                controller: inputController,
                hintText: hint,
                actionLabel: context.t(LocaleKeys.commonAdd),
                onActionPressed: addModel,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
