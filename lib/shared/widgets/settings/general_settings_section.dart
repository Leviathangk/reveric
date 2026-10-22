// 职责: 共享通用设置区 — 语言选择（中文简体 / English）与匿名诊断上报同意。
// 关联文件:
//   lib/shared/providers/settings_providers.dart
//   lib/shared/providers/anonymous_reporting_providers.dart
//   lib/shared/app_config.dart
//   lib/shared/components/reveric_switch.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../app_config.dart';
import '../../components/reveric_switch.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/anonymous_reporting_providers.dart';
import '../../providers/settings_providers.dart';
import '../../theme/theme.dart';

/// 通用设置 section（语言切换、匿名诊断上报）。
class GeneralSettingsSection extends HookConsumerWidget {
  const GeneralSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    final currentLocale = context.locale;

    Future<void> updateLocale(Locale nextLocale) async {
      if (currentLocale == nextLocale) {
        return;
      }
      await context.setLocale(nextLocale);
      await settingsNotifier.setLanguage(
        nextLocale.toLanguageTag().replaceAll('-', '_'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context: context,
            titleKey: LocaleKeys.settingsLanguageSection,
            descriptionKey: LocaleKeys.settingsLanguageDescription,
          ),
          const SizedBox(height: RevericSpacing.xl),
          _buildLanguageCard(
            context: context,
            labelKey: LocaleKeys.settingsChineseSimplified,
            locale: const Locale('zh', 'CN'),
            isSelected: currentLocale == const Locale('zh', 'CN'),
            onTap: () => updateLocale(const Locale('zh', 'CN')),
          ),
          const SizedBox(height: RevericSpacing.md),
          _buildLanguageCard(
            context: context,
            labelKey: LocaleKeys.settingsEnglish,
            locale: const Locale('en'),
            isSelected: currentLocale == const Locale('en'),
            onTap: () => updateLocale(const Locale('en')),
          ),
          // 本构建未配置上报地址时同意无效，不展示入口。
          if (anonymousReportingBaseUrl.isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.x3l),
            _buildSectionHeader(
              context: context,
              titleKey: LocaleKeys.settingsPrivacySection,
              descriptionKey: LocaleKeys.settingsPrivacyDescription,
            ),
            const SizedBox(height: RevericSpacing.xl),
            const _AnonymousReportingCard(),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required BuildContext context,
    required String titleKey,
    required String descriptionKey,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t(titleKey),
          style: typo.uiSemibold.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: RevericSpacing.xs),
        Text(
          context.t(descriptionKey),
          style: typo.ui.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }

  Widget _buildLanguageCard({
    required BuildContext context,
    required String labelKey,
    required Locale locale,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Material(
      color: isSelected ? colors.selected : colors.canvas,
      borderRadius: BorderRadius.circular(RevericRadius.large),
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.hover,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(RevericSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(
              color: isSelected ? colors.accent : colors.borderInput,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t(labelKey),
                      style: typo.uiSemibold.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: RevericSpacing.xxs),
                    Text(
                      locale.toLanguageTag(),
                      style: typo.uiSmall.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                RevericIcon(
                  RevericIcons.check_circle,
                  color: colors.accent,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnonymousReportingCard extends ConsumerWidget {
  const _AnonymousReportingCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    // 加载完成前禁用开关，不用默认值冒充真实同意状态。
    final consent = ref.watch(anonymousReportingConsentProvider).value;
    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t(LocaleKeys.settingsAnonymousReporting),
                  style: typo.uiSemibold.copyWith(color: colors.textPrimary),
                ),
                const SizedBox(height: RevericSpacing.xxs),
                Text(
                  context.t(LocaleKeys.settingsAnonymousReportingDescription),
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: RevericSpacing.lg),
          RevericSwitch(
            value: consent ?? false,
            onChanged: consent == null
                ? null
                : ref.read(anonymousReportingConsentProvider.notifier).set,
          ),
        ],
      ),
    );
  }
}
