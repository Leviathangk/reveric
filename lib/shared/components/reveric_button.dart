// 职责: 统一普通操作按钮的语义、尺寸、图标与加载反馈，继承全局按钮主题。
// 关联文件:
//   lib/shared/theme/reveric_theme.dart
//   lib/shared/theme/reveric_spacing.dart
//   lib/shared/theme/reveric_icons.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/icons.md

import 'package:flutter/material.dart';

import '../theme/theme.dart';

enum RevericButtonSize { standard, compact }

enum _ButtonVariant { primary, secondary, text, danger }

/// 普通操作按钮；调用方持有异步状态，组件只展示 loading 并阻止再次点击。
class RevericButton extends StatelessWidget {
  const RevericButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.labelMaxLines,
    this.loading = false,
    this.size = RevericButtonSize.standard,
  }) : _variant = _ButtonVariant.primary;

  const RevericButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.labelMaxLines,
    this.loading = false,
    this.size = RevericButtonSize.standard,
  }) : _variant = _ButtonVariant.secondary;

  const RevericButton.text({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.labelMaxLines,
    this.loading = false,
    this.size = RevericButtonSize.standard,
  }) : _variant = _ButtonVariant.text;

  /// 破坏性确认操作，沿用设计系统的删除语义色。
  const RevericButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.labelMaxLines,
    this.loading = false,
    this.size = RevericButtonSize.standard,
  }) : _variant = _ButtonVariant.danger;

  final String label;
  final int? labelMaxLines;
  final VoidCallback? onPressed;
  final String? icon;
  final bool loading;
  final RevericButtonSize size;
  final _ButtonVariant _variant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = RevericTheme.colorsOf(context);
    final mobile = switch (theme.platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final compact = size == RevericButtonSize.compact;
    final danger = _variant == _ButtonVariant.danger;
    final dangerBackground = theme.brightness == Brightness.dark
        ? Color.alphaBlend(
            colors.canvas.withValues(alpha: 0.2),
            colors.deletionBorder,
          )
        : colors.deletionBorder;
    final backgroundLuminance = dangerBackground.computeLuminance();
    double contrast(Color foreground) {
      final luminance = foreground.computeLuminance();
      return luminance > backgroundLuminance
          ? (luminance + 0.05) / (backgroundLuminance + 0.05)
          : (backgroundLuminance + 0.05) / (luminance + 0.05);
    }

    // 主色按钮的 onAccent 不一定适合红色背景；从主题中选对比更高的文字色。
    final dangerForeground =
        contrast(colors.canvas) > contrast(colors.textPrimary)
        ? colors.canvas
        : colors.textPrimary;
    final style = ButtonStyle(
      minimumSize: compact
          ? const WidgetStatePropertyAll(Size(0, RevericSizes.buttonHeightSm))
          : null,
      padding: compact
          ? const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: RevericSizes.buttonPaddingHSm),
            )
          : null,
      tapTargetSize: mobile
          ? MaterialTapTargetSize.padded
          : MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.standard,
      foregroundColor: danger
          ? WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? dangerForeground.withValues(alpha: 0.7)
                  : dangerForeground;
            })
          : null,
      backgroundColor: danger
          ? WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.disabled)
                  ? dangerBackground.withValues(alpha: 0.4)
                  : dangerBackground;
            })
          : null,
    );
    final child = _ButtonContent(
      label: label,
      icon: icon,
      loading: loading,
      labelMaxLines: labelMaxLines,
    );
    final callback = loading ? null : onPressed;
    return switch (_variant) {
      _ButtonVariant.primary || _ButtonVariant.danger => FilledButton(
        onPressed: callback,
        style: style,
        child: child,
      ),
      _ButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        style: style,
        child: child,
      ),
      _ButtonVariant.text => TextButton(
        onPressed: callback,
        style: style,
        child: child,
      ),
    };
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.loading,
    required this.labelMaxLines,
  });

  final String label;
  final int? labelMaxLines;
  final String? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final foreground = DefaultTextStyle.of(context).style.color;
    final indicator = loading
        ? CircularProgressIndicator(
            strokeWidth: RevericSizes.buttonProgressStroke,
            color: foreground,
          )
        : icon == null
        ? null
        : RevericIcon(
            icon!,
            color: foreground,
            size: RevericSizes.buttonIconSize,
          );
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: RevericSizes.buttonIconSize,
          child: indicator,
        ),
        const SizedBox(width: RevericSpacing.sm),
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: labelMaxLines,
            overflow: labelMaxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
    if (icon != null) {
      return row;
    }
    // 无图标按钮也预留加载所需宽度；仅移动内边距，不复制或隐藏文案。
    const leadingWidth = RevericSizes.buttonIconSize + RevericSpacing.sm;
    return Stack(
      alignment: Alignment.center,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: loading ? leadingWidth : leadingWidth / 2,
            end: loading ? 0 : leadingWidth / 2,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: labelMaxLines,
            overflow: labelMaxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
        if (loading)
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: SizedBox.square(
                dimension: RevericSizes.buttonIconSize,
                child: indicator,
              ),
            ),
          ),
      ],
    );
  }
}
