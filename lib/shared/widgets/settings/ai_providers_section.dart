// 职责: 共享 AI provider 设置区 — provider 列表、自定义 provider 弹窗、provider 配置表单（含获取模型）。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/models/ai_provider.dart
//   lib/shared/components/reveric_text_field.dart
//   lib/shared/localization/ai_provider_localization.dart
//   lib/shared/components/reveric_select.dart
//   lib/shared/localization/locale_keys.dart
//   lib/shared/theme/theme.dart
//   lib/desktop/widgets/settings/settings_dialog.dart
//   lib/shared/widgets/settings/mobile_provider_list.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/state-management.md
//   .agents/rules/hooks.md

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_badge.dart';
import '../../components/reveric_placeholder.dart';
import '../../components/reveric_select.dart';
import '../../components/reveric_text_field.dart';
import '../../localization/ai_provider_localization.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../models/ai_provider.dart';
import '../../providers/settings_providers.dart';
import '../../theme/theme.dart';
import '../../utils/random_id.dart';
import 'mobile_provider_list.dart';
import 'provider_config_panel.dart';
import '../../components/reveric_dialog.dart';
import '../../components/reveric_button.dart';

/// AI providers section：左侧 provider 列表 + 右侧配置面板（桌面），
/// 或纯列表 + push 到配置页（移动端及宽度 < 600 的窗口）。
class AiProvidersSection extends HookConsumerWidget {
  const AiProvidersSection({super.key});

  /// 「查看套餐」动作（桌面端切设置导航，移动端 push 套餐页）。

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    // 移动端调用方普遍不传 onOpenPlans（设置子页无法切换导航），兜底到全屏套餐页，
    // 否则升级引导里的「查看套餐」点了只会关窗。

    final settingsAsync = ref.watch(appSettingsProvider);

    final selectedId = useState<String?>(null);

    return settingsAsync.when(
      loading: () => Center(
        child: SizedBox(
          width: RevericSizes.aiAvatarMd,
          height: RevericSizes.aiAvatarMd,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.accent,
          ),
        ),
      ),
      error: (_, _) => Center(
        child: RevericPlaceholder.error(
          title: context.t(LocaleKeys.commonLoadFailed),
        ),
      ),
      data: (settings) => _AiProvidersLoadedView(
        settings: settings,

        selectedProviderId: selectedId.value,

        onSelectProvider: (id) => selectedId.value = id,
        onAddCustom: () {
          _showAddCustomProviderDialog(context, ref).then((newId) {
            if (newId != null) {
              selectedId.value = newId;
            }
          });
        },
      ),
    );
  }

  Future<String?> _showAddCustomProviderDialog(
    BuildContext context,
    WidgetRef ref,
  ) {
    return showRevericDialog<String>(
      context: context,
      builder: (ctx) => AddCustomProviderDialog(
        onAdd: (name, format) async {
          final id = buildRandomId('prv', length: 6);
          final config = AiProvider(
            audioModels: const [],
            videoModels: const [],
            id: id,
            name: name,
            builtin: false,
            type: format.name,
            enabled: false,
            apiKey: '',
            baseUrl: aiProviderTypeConfigs[format]?.fixedBaseUrl == true
                ? aiProviderFixedBaseUrl(format)
                : format == AiProviderType.agnes
                ? agnesDefaultBaseUrl
                : '',
            models: const [],
            imageModels: const [],
            deletedAt: DateTime.fromMillisecondsSinceEpoch(0),
            embeddingModels: const [],
            temperature: 0.7,
            maxTurns: 512,
            proxyUrl: '',
            proxyUsername: '',
            proxyPassword: '',
            updatedAt: DateTime.now(),
          );
          await ref
              .read(appSettingsProvider.notifier)
              .addCustomProvider(config);
          return id;
        },
      ),
    );
  }
}

class _AiProvidersLoadedView extends StatelessWidget {
  final AppSettings settings;

  final String? selectedProviderId;

  final ValueChanged<String> onSelectProvider;
  final VoidCallback onAddCustom;

  const _AiProvidersLoadedView({
    required this.settings,

    required this.selectedProviderId,

    required this.onSelectProvider,
    required this.onAddCustom,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final allConfigs = settings.aiSettings.allConfigs;

    final effectiveSelectedId =
        allConfigs.any((c) => c.id == selectedProviderId)
        ? selectedProviderId
        : (allConfigs.isNotEmpty ? allConfigs.first.id : null);

    final selectedConfig = effectiveSelectedId != null
        ? settings.aiSettings.findConfigById(effectiveSelectedId)
        : null;

    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final isDesktop = !isMobile && MediaQuery.sizeOf(context).width >= 600;

    if (isDesktop) {
      return Row(
        children: [
          SizedBox(
            width: RevericSizes.settingsProviderListWidth,
            child: ProviderList(
              configs: allConfigs,

              selectedId: effectiveSelectedId,

              onSelect: onSelectProvider,
              onAddCustom: onAddCustom,
            ),
          ),
          Container(width: RevericSizes.dividerThickness, color: colors.border),
          Expanded(
            child: selectedConfig != null
                ? ProviderConfigPanel(
                    key: ValueKey(selectedConfig.id),
                    providerId: selectedConfig.id,
                  )
                : Center(
                    child: Text(
                      context.t(LocaleKeys.settingsProviderSelectPlaceholder),
                      style: RevericTheme.typographyOf(
                        context,
                      ).ui.copyWith(color: colors.textMuted),
                    ),
                  ),
          ),
        ],
      );
    }

    // 移动端：分组卡片列表，点击进入配置页。
    return MobileProviderList(
      configs: allConfigs,

      selectedId: effectiveSelectedId,

      onSelect: (id) {
        final config = settings.aiSettings.findConfigById(id);
        if (config == null) {
          return;
        }
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _ProviderConfigRoute(
              title: localizedAiProviderName(context, config),
              providerId: config.id,
            ),
          ),
        );
      },
      onAddCustom: onAddCustom,
    );
  }
}

class _ProviderConfigRoute extends StatelessWidget {
  const _ProviderConfigRoute({required this.title, required this.providerId});

  final String title;
  final String providerId;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.surfaceDim,
        elevation: 0,
        leading: IconButton(
          icon: RevericIcon(RevericIcons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: typo.heading2.copyWith(color: colors.textPrimary),
        ),
      ),
      body: ProviderConfigPanel(
        providerId: providerId,

        onDeleted: () => Navigator.of(context).pop(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider List
// ─────────────────────────────────────────────────────────────────────────────

class ProviderList extends StatelessWidget {
  final List<AiProvider> configs;

  final String? selectedId;

  final ValueChanged<String> onSelect;
  final VoidCallback onAddCustom;

  const ProviderList({
    super.key,
    required this.configs,

    required this.selectedId,

    required this.onSelect,
    required this.onAddCustom,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Container(
      color: colors.surfaceDim,
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: RevericSpacing.xs,
                vertical: RevericSpacing.sm,
              ),
              itemCount: configs.length,
              itemBuilder: (ctx, i) {
                final config = configs[i];
                final isSelected = config.id == selectedId;
                return ProviderListItem(
                  config: config,

                  isSelected: isSelected,
                  locked: false,
                  onTap: () => onSelect(config.id),
                );
              },
            ),
          ),
          Container(
            height: RevericSizes.dividerThickness,
            color: colors.border,
          ),
          Padding(
            padding: const EdgeInsets.all(RevericSpacing.sm),
            child: SizedBox(
              width: double.infinity,
              child: RevericButton.secondary(
                label: context.t(LocaleKeys.settingsAddCustomProvider),
                icon: RevericIcons.add,
                size: RevericButtonSize.compact,
                onPressed: onAddCustom,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ProviderListItem extends StatelessWidget {
  final AiProvider config;

  final bool isSelected;
  final bool locked;
  final VoidCallback onTap;

  const ProviderListItem({
    super.key,
    required this.config,

    required this.isSelected,
    this.locked = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Material(
      color: isSelected ? colors.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: InkWell(
        onTap: onTap,
        hoverColor: colors.hover,
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          child: Row(
            children: [
              ProviderStatusDot(
                active: config.isValid,
                size: RevericSizes.statusDotSize,
              ),
              const SizedBox(width: RevericSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            localizedAiProviderName(context, config),
                            style:
                                (isSelected
                                        ? typo.uiSmallSemibold
                                        : typo.uiSmall)
                                    .copyWith(color: colors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (!config.isTypeSupported || !config.isBuiltin) ...[
                      const SizedBox(height: RevericSpacing.xxs),
                      RevericBadge(
                        label: context.t(
                          config.isTypeSupported
                              ? LocaleKeys.settingsCustomBadge
                              : LocaleKeys.settingsProviderUnsupportedBadge,
                        ),
                        color: config.isTypeSupported
                            ? colors.accentWarm
                            : colors.warningText,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Badge
// ─────────────────────────────────────────────────────────────────────────────

class StatusBadge extends StatelessWidget {
  final bool isValid;
  const StatusBadge({super.key, required this.isValid});

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return RevericBadge(
      label: context.t(
        isValid
            ? LocaleKeys.settingsStatusActive
            : LocaleKeys.settingsStatusInactive,
      ),
      color: isValid ? colors.additionBorder : colors.textMuted,
    );
  }
}

/// 列表项左侧的可用状态圆点；悬停给出与 [StatusBadge] 相同的状态文案。
class ProviderStatusDot extends StatelessWidget {
  final bool active;
  final double size;
  const ProviderStatusDot({
    super.key,
    required this.active,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Tooltip(
      message: context.t(
        active
            ? LocaleKeys.settingsStatusActive
            : LocaleKeys.settingsStatusInactive,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? colors.additionBorder : colors.border,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Custom Provider Dialog
// ─────────────────────────────────────────────────────────────────────────────

class AddCustomProviderDialog extends HookWidget {
  final Future<String> Function(String name, AiProviderType format) onAdd;

  const AddCustomProviderDialog({super.key, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final nameController = useTextEditingController();
    final selectedFormat = useState(AiProviderType.openai_compatible);
    final isAdding = useState(false);
    final hasName = useListenableSelector(
      nameController,
      () => nameController.text.trim().isNotEmpty,
    );

    return RevericDialog.panel(
      title: Text(context.t(LocaleKeys.settingsAddCustomProviderTitle)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RevericTextField(
            controller: nameController,
            autofocus: true,
            label: context.t(LocaleKeys.settingsAddCustomProviderNameLabel),
            hintText: context.t(LocaleKeys.settingsAddCustomProviderNameHint),
          ),
          const SizedBox(height: RevericSpacing.lg),
          RevericSelect<AiProviderType>(
            label: context.t(LocaleKeys.settingsAddCustomProviderTypeLabel),
            value: selectedFormat.value,
            items: [
              for (final format in customAiProviderTypes.where(
                (type) =>
                    type != AiProviderType.minimax ||
                    (Theme.of(context).platform != TargetPlatform.android &&
                        Theme.of(context).platform != TargetPlatform.iOS),
              ))
                if (format != AiProviderType.codex ||
                    (defaultTargetPlatform != TargetPlatform.android &&
                        defaultTargetPlatform != TargetPlatform.iOS))
                  RevericSelectItem<AiProviderType>(
                    value: format,
                    label: localizedProviderTypeName(context, format),
                  ),
            ],
            onChanged: (format) => selectedFormat.value = format,
          ),
        ],
      ),
      actions: [
        RevericButton.secondary(
          label: context.t(LocaleKeys.commonCancel),
          onPressed: () => Navigator.of(context).pop(),
        ),
        RevericButton.primary(
          label: context.t(LocaleKeys.commonAdd),
          loading: isAdding.value,
          onPressed: !hasName
              ? null
              : () async {
                  final name = nameController.text.trim();
                  isAdding.value = true;
                  final newId = await onAdd(name, selectedFormat.value);
                  if (context.mounted) {
                    Navigator.of(context).pop(newId);
                  }
                },
        ),
      ],
    );
  }
}

/// Provider 类型展示名；兼容协议名称及有中英文品牌名的渠道走 locale key。
String localizedProviderTypeName(BuildContext context, AiProviderType type) {
  if (type == AiProviderType.volcengine) {
    return context.t(LocaleKeys.settingsProviderTypeVolcengine);
  }
  if (type == AiProviderType.openai_compatible) {
    return context.t(LocaleKeys.settingsProviderTypeOpenaiCompatible);
  }
  return aiProviderTypeDisplayNames[type] ?? type.name;
}
