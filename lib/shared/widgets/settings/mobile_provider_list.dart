// 职责: 展示移动端供应商分组列表，支持详情导航和左滑确认删除。
// 关联文件:
//   lib/shared/widgets/settings/ai_providers_section.dart
//   lib/shared/models/ai_provider.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/widgets/settings/provider_actions.dart
//   lib/shared/components/reveric_slidable_delete.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_badge.dart';
import '../../components/reveric_slidable_delete.dart';
import '../../localization/ai_provider_localization.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/ai_provider.dart';
import '../../providers/settings_providers.dart';
import '../../theme/theme.dart';
import 'ai_providers_section.dart';
import 'provider_actions.dart';

/// 移动端供应商列表：全宽分组卡片，每行下钻到配置页。
/// 与 `lib/mobile/pages/settings_page.dart` 主设置列表保持一致的视觉规范。
class MobileProviderList extends ConsumerWidget {
  final List<AiProvider> configs;

  final String? selectedId;

  final ValueChanged<String> onSelect;
  final VoidCallback onAddCustom;

  const MobileProviderList({
    super.key,
    required this.configs,

    required this.selectedId,

    required this.onSelect,
    required this.onAddCustom,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.x3l,
        RevericSpacing.lg,
        RevericSpacing.x3l,
        RevericSpacing.x4l,
      ),
      children: [
        Container(
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.x2l),
            border: Border.all(color: colors.borderSubtle),
          ),
          child: Column(
            children: [
              for (var i = 0; i < configs.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: colors.borderSubtle),
                if (configs[i].canDelete)
                  RevericSlidableDelete(
                    key: ValueKey(configs[i].id),
                    borderRadius: BorderRadius.zero,
                    deleteLabel: context.t(LocaleKeys.commonDelete),
                    onDelete: () async {
                      final notifier = ref.read(appSettingsProvider.notifier);
                      await confirmDeleteProvider(
                        context,
                        config: configs[i],
                        onDelete: () => notifier.removeProvider(configs[i].id),
                      );
                    },
                    childBuilder: (context, _) => Material(
                      color: colors.surface,
                      child: _MobileProviderRow(
                        config: configs[i],

                        locked: false,
                        onTap: () => onSelect(configs[i].id),
                      ),
                    ),
                  )
                else
                  _MobileProviderRow(
                    key: ValueKey(configs[i].id),
                    config: configs[i],

                    locked: false,
                    onTap: () => onSelect(configs[i].id),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: RevericSpacing.x3l),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: onAddCustom,
            icon: const RevericIcon(RevericIcons.add, size: 16),
            label: Text(context.t(LocaleKeys.settingsAddCustomProvider)),
            style: TextButton.styleFrom(
              foregroundColor: colors.accent,
              minimumSize: const Size(0, RevericSizes.buttonHeight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(RevericRadius.button),
                side: BorderSide(color: colors.borderInput),
              ),
              textStyle: typo.ui,
            ),
          ),
        ),
      ],
    );
  }
}

class _MobileProviderRow extends StatelessWidget {
  final AiProvider config;

  final bool locked;
  final VoidCallback onTap;

  const _MobileProviderRow({
    super.key,
    required this.config,

    this.locked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final providerName = localizedAiProviderName(context, config);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.xl,
          vertical: RevericSpacing.lg,
        ),
        child: Row(
          children: [
            ProviderStatusDot(
              active: config.isValid,
              size: RevericSizes.statusDotSizeMobile,
            ),
            const SizedBox(width: RevericSpacing.lg),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      providerName,
                      style: typo.ui.copyWith(color: colors.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (!config.isTypeSupported || !config.isBuiltin) ...[
                    const SizedBox(width: RevericSpacing.sm),
                    Flexible(
                      child: RevericBadge(
                        label: !config.isTypeSupported
                            ? context.t(
                                LocaleKeys.settingsProviderUnsupportedBadge,
                              )
                            : context.t(LocaleKeys.settingsCustomBadge),
                        color: !config.isTypeSupported
                            ? colors.warningText
                            : colors.accentWarm,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: RevericSpacing.sm),
            RevericIcon(
              RevericIcons.keyboard_arrow_right,
              size: 18,
              color: colors.textSubtle,
            ),
          ],
        ),
      ),
    );
  }
}
