// 职责: 展示跨平台插件列表、加载反馈与运行状态。
// 关联文件:
//   lib/shared/widgets/settings/plugins/row.dart
//   lib/shared/providers/plugin_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../localization/app_localization.dart';
import '../../../localization/locale_keys.dart';
import '../../../providers/plugin_providers.dart';
import '../../../theme/theme.dart';
import '../settings_section_widgets.dart';
import 'row.dart';

class PluginsSettingsSection extends ConsumerWidget {
  const PluginsSettingsSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plugins = ref.watch(pluginStatusesProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: SettingsSection(
        titleKey: LocaleKeys.settingsPlugins,
        descriptionKey: LocaleKeys.settingsPluginsDescription,
        child: plugins.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => Text(
            context.t(LocaleKeys.settingsPluginsLoadFailed),
            style: RevericTheme.typographyOf(
              context,
            ).ui.copyWith(color: RevericTheme.colorsOf(context).warningText),
          ),
          data: (items) => items.isEmpty
              ? Text(
                  context.t(LocaleKeys.settingsPluginsEmpty),
                  style: RevericTheme.typographyOf(context).ui.copyWith(
                    color: RevericTheme.colorsOf(context).textMuted,
                  ),
                )
              : SettingsCard(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final (index, item) in items.indexed) ...[
                      if (index > 0) const SettingsRowDivider(),
                      PluginSettingsRow(key: ValueKey(item.id), status: item),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
