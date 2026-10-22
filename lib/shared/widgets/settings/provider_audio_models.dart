// 职责: 在共享供应商表单中编辑音频模型列表并展示配置说明。
// 关联文件:
//   lib/shared/widgets/settings/provider_config_panel.dart
//   lib/shared/widgets/settings/provider_models_editor.dart
//   lib/shared/models/ai_provider.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/ai_provider.dart';
import '../../models/audio/channels.dart' show AudioProtocol;
import '../../theme/theme.dart';
import 'provider_models_editor.dart';

class ProviderAudioModels extends StatelessWidget {
  const ProviderAudioModels({
    super.key,
    required this.config,
    required this.onChanged,
    this.fetchButton,
  });
  final AiProvider config;
  final ValueChanged<List<String>> onChanged;
  final Widget? fetchButton;

  @override
  Widget build(BuildContext context) {
    if (!config.supportsModelKind(AiModelKind.audio)) {
      return const SizedBox.shrink();
    }
    final typo = RevericTheme.typographyOf(context);
    final colors = RevericTheme.colorsOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProviderModelsEditor(
          key: ValueKey(config.id),
          label: context.t(LocaleKeys.settingsProviderAudioModelsLabel),
          hint: context.t(LocaleKeys.settingsProviderModelIdHint),
          models: config.availableAudioModels,
          onChanged: onChanged,
          fetchButton: fetchButton,
        ),
        const SizedBox(height: RevericSpacing.xs),
        Text(
          context.t(switch (config.typeConfig.audioProtocol!) {
            AudioProtocol.openrouter_speech =>
              LocaleKeys.settingsProviderOpenrouterAudioHint,
            AudioProtocol.minimax_music =>
              LocaleKeys.settingsProviderMinimaxAudioHint,
            AudioProtocol.seed_audio =>
              LocaleKeys.settingsProviderVolcengineAudioHint,
          }),
          style: typo.uiSmall.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }
}
