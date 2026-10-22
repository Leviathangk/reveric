// 职责: 在浮窗自己的 Overlay 中展示操作菜单，确认后清空聊天消息。
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/global_floating_chat.dart
//   lib/shared/components/reveric_icon_button.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/floating_chat.json
//   assets/translations/zh-CN/floating_chat.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/hooks.md
//   .agents/rules/icons.md
//   .agents/rules/i18n.md

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../components/reveric_icon_button.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../theme/theme.dart';
import '../components/reveric_dialog.dart';
import '../components/reveric_button.dart';

class FloatingChatActions extends HookWidget {
  const FloatingChatActions({super.key, required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final confirmation = useMemoized(OverlayPortalController.new);

    // 浮窗和主 Navigator 是兄弟节点。菜单及确认都使用本地 Overlay，
    // 避免找不到 Navigator，或把确认窗口画在浮窗背后。
    return OverlayPortal(
      controller: confirmation,
      overlayChildBuilder: (context) => Positioned.fill(
        child: Stack(
          children: [
            ModalBarrier(
              color: colors.textPrimary.withValues(alpha: 0.32),
              dismissible: true,
              onDismiss: confirmation.hide,
              semanticsLabel: context.t(LocaleKeys.commonCancel),
            ),
            Center(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape):
                      confirmation.hide,
                },
                child: FocusScope(
                  autofocus: true,
                  child: RevericDialog(
                    title: context.t(LocaleKeys.floatingChatClear),
                    content: Text(
                      context.t(LocaleKeys.floatingChatClearConfirm),
                    ),
                    actions: [
                      RevericButton.secondary(
                        label: context.t(LocaleKeys.commonCancel),
                        onPressed: confirmation.hide,
                      ),
                      RevericButton.danger(
                        label: context.t(LocaleKeys.floatingChatClear),
                        onPressed: () {
                          confirmation.hide();
                          onClear();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      child: MenuAnchor(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surface),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.all(RevericSpacing.xs),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(RevericRadius.large),
              side: BorderSide(color: colors.border),
            ),
          ),
        ),
        menuChildren: [
          MenuItemButton(
            onPressed: confirmation.show,
            leadingIcon: RevericIcon(
              RevericIcons.delete_outline,
              size: 18,
              color: colors.warningText,
            ),
            child: Text(
              context.t(LocaleKeys.floatingChatClear),
              style: typo.uiSmall.copyWith(color: colors.warningText),
            ),
          ),
        ],
        builder: (context, menu, _) => RevericIconButton(
          icon: RevericIcons.more_horiz,
          tooltip: context.t(LocaleKeys.commonMoreActions),
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        ),
      ),
    );
  }
}
