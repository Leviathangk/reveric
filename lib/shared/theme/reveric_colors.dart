import 'package:flutter/material.dart';

class RevericColors {
  final Brightness brightness;

  // Surfaces
  final Color canvas;
  final Color surface;
  final Color surfaceDim;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;

  // Borders
  final Color border;
  final Color borderSubtle;
  final Color borderInput;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textSubtle;

  // Accent
  final Color accent;
  final Color accentWarm;
  final Color accentAmber;

  // States
  final Color selected;
  final Color hover;

  // Semantic
  final Color deletionBg;
  final Color deletionBorder;
  final Color additionBg;
  final Color additionBorder;
  final Color warningBg;
  final Color warningText;
  final Color success;
  final Color error;

  // Blockquote
  final Color blockquoteBorder;

  // Accent contrast (text/icon on accent background)
  final Color onAccent;

  // Text
  final Color textTertiary;

  const RevericColors({
    required this.brightness,
    required this.canvas,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.border,
    required this.borderSubtle,
    required this.borderInput,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.accentWarm,
    required this.accentAmber,
    required this.selected,
    required this.hover,
    required this.deletionBg,
    required this.deletionBorder,
    required this.additionBg,
    required this.additionBorder,
    required this.warningBg,
    required this.warningText,
    required this.success,
    required this.error,
    required this.blockquoteBorder,
    required this.onAccent,
    required this.textTertiary,
  });

  bool get isDark => brightness == Brightness.dark;

  /// Reveric — ivory paper and ink navy, taken from the brand mark.
  /// The default theme for creative writing.
  static const reveric = RevericColors(
    brightness: Brightness.light,
    canvas: Color(0xFFFEFCF9),
    surface: Color(0xFFFBFAF7),
    surfaceDim: Color(0xFFF4F3F0),
    surfaceContainer: Color(0xFFF8F7F4),
    surfaceContainerHigh: Color(0xFFFCFBF9),
    border: Color(0xFFE6E5E2),
    borderSubtle: Color(0xFFEFEEEB),
    borderInput: Color(0xFFE3E3E1),
    textPrimary: Color(0xFF1F2A3D),
    textSecondary: Color(0xFF4A5468),
    textMuted: Color(0xFF7E8698),
    textSubtle: Color(0xFFADB2BF),
    accent: Color(0xFF283C5F),
    accentWarm: Color(0xFF3B5182),
    accentAmber: Color(0xFF8897D1),
    selected: Color(0xFFEEF0F8),
    hover: Color(0xFFF3F4F8),
    deletionBg: Color(0xFFFDE8E8),
    deletionBorder: Color(0xFFC53030),
    additionBg: Color(0xFFE8F5E8),
    additionBorder: Color(0xFF4A7C59),
    warningBg: Color(0xFFFEF3C7),
    warningText: Color(0xFFD97706),
    blockquoteBorder: Color(0xFF8897D1),
    textTertiary: Color(0xFF7E8698),
    success: Color(0xFF4A7C59),
    error: Color(0xFFC53030),
    onAccent: Color(0xFFFFFFFF),
  );

  /// 深色下深墨蓝压不住背景，主色换成长春花蓝。
  static const revericDark = RevericColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF12161F),
    surface: Color(0xFF181D28),
    surfaceDim: Color(0xFF1D2330),
    surfaceContainer: Color(0xFF202736),
    surfaceContainerHigh: Color(0xFF262E3F),
    border: Color(0xFF2E3647),
    borderSubtle: Color(0xFF252C3B),
    borderInput: Color(0xFF353E51),
    textPrimary: Color(0xFFE9ECF3),
    textSecondary: Color(0xFFC2C8D6),
    textMuted: Color(0xFF8E97AB),
    textSubtle: Color(0xFF636C80),
    accent: Color(0xFF8897D1),
    accentWarm: Color(0xFFA3B0E0),
    accentAmber: Color(0xFFB8C2EC),
    selected: Color(0xFF2A3346),
    hover: Color(0xFF232A39),
    deletionBg: Color(0xFF3D1F1F),
    deletionBorder: Color(0xFFE53E3E),
    additionBg: Color(0xFF1F3D2A),
    additionBorder: Color(0xFF48BB78),
    warningBg: Color(0xFF3D331F),
    warningText: Color(0xFFF6AD55),
    blockquoteBorder: Color(0xFF8897D1),
    textTertiary: Color(0xFF8E97AB),
    success: Color(0xFF48BB78),
    error: Color(0xFFE53E3E),
    onAccent: Color(0xFF12161F),
  );

  /// Classic black & white theme — minimal, timeless, high contrast.
  static const classic = RevericColors(
    brightness: Brightness.light,
    canvas: Color(0xFFFFFFFF),
    surface: Color(0xFFFAFAFA),
    surfaceDim: Color(0xFFF0F0F0),
    surfaceContainer: Color(0xFFF5F5F5),
    surfaceContainerHigh: Color(0xFFFFFFFF),
    border: Color(0xFFE0E0E0),
    borderSubtle: Color(0xFFEEEEEE),
    borderInput: Color(0xFFD0D0D0),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF333333),
    textMuted: Color(0xFF666666),
    textSubtle: Color(0xFF999999),
    accent: Color(0xFF000000),
    accentWarm: Color(0xFF333333),
    accentAmber: Color(0xFF666666),
    selected: Color(0xFFE8E8E8),
    hover: Color(0xFFF2F2F2),
    deletionBg: Color(0xFFFEE2E2),
    deletionBorder: Color(0xFFDC2626),
    additionBg: Color(0xFFD1FAE5),
    additionBorder: Color(0xFF059669),
    warningBg: Color(0xFFFEF9C3),
    warningText: Color(0xFFA16207),
    blockquoteBorder: Color(0xFFCCCCCC),
    textTertiary: Color(0xFF666666),
    success: Color(0xFF059669),
    error: Color(0xFFDC2626),
    onAccent: Color(0xFFFFFFFF),
  );

  static const classicDark = RevericColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF000000),
    surface: Color(0xFF0A0A0A),
    surfaceDim: Color(0xFF141414),
    surfaceContainer: Color(0xFF1A1A1A),
    surfaceContainerHigh: Color(0xFF242424),
    border: Color(0xFF2A2A2A),
    borderSubtle: Color(0xFF1F1F1F),
    borderInput: Color(0xFF333333),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFCCCCCC),
    textMuted: Color(0xFF888888),
    textSubtle: Color(0xFF666666),
    accent: Color(0xFFFFFFFF),
    accentWarm: Color(0xFFCCCCCC),
    accentAmber: Color(0xFF888888),
    selected: Color(0xFF2A2A2A),
    hover: Color(0xFF333333),
    deletionBg: Color(0xFF2A1414),
    deletionBorder: Color(0xFFEF4444),
    additionBg: Color(0xFF142A1C),
    additionBorder: Color(0xFF10B981),
    warningBg: Color(0xFF2A2614),
    warningText: Color(0xFFFBBF24),
    blockquoteBorder: Color(0xFF444444),
    textTertiary: Color(0xFF888888),
    success: Color(0xFF10B981),
    error: Color(0xFFEF4444),
    onAccent: Color(0xFF000000),
  );

  /// Ivory — warm and gentle, like aged paper and cream.
  static const ivory = RevericColors(
    brightness: Brightness.light,
    canvas: Color(0xFFF8F8F0),
    surface: Color(0xFFFAFAF3),
    surfaceDim: Color(0xFFEBECDC),
    surfaceContainer: Color(0xFFF1F2E5),
    surfaceContainerHigh: Color(0xFFF5F6EC),
    border: Color(0xFFDADBC4),
    borderSubtle: Color(0xFFECEDDC),
    borderInput: Color(0xFFDEDFCA),
    textPrimary: Color(0xFF2E3026),
    textSecondary: Color(0xFF555848),
    textMuted: Color(0xFF767866),
    textSubtle: Color(0xFF92957F),
    accent: Color(0xFFA2AF9B),
    accentWarm: Color(0xFF8B9A8A),
    accentAmber: Color(0xFFC4956A),
    selected: Color(0xFFE2E3CD),
    hover: Color(0xFFEBECDC),
    deletionBg: Color(0xFFFDE8E8),
    deletionBorder: Color(0xFFC53030),
    additionBg: Color(0xFFE8FDE8),
    additionBorder: Color(0xFF2F855A),
    warningBg: Color(0xFFFEF3C7),
    warningText: Color(0xFFD97706),
    blockquoteBorder: Color(0xFFD4A574),
    textTertiary: Color(0xFF767866),
    success: Color(0xFF2F855A),
    error: Color(0xFFC53030),
    onAccent: Color(0xFF2E3026),
  );

  static const ivoryDark = RevericColors(
    brightness: Brightness.dark,
    canvas: Color(0xFF141410),
    surface: Color(0xFF1C1C16),
    surfaceDim: Color(0xFF252520),
    surfaceContainer: Color(0xFF2A2A24),
    surfaceContainerHigh: Color(0xFF34342E),
    border: Color(0xFF3E3E36),
    borderSubtle: Color(0xFF323228),
    borderInput: Color(0xFF484840),
    textPrimary: Color(0xFFEBECDC),
    textSecondary: Color(0xFFB8B8A6),
    textMuted: Color(0xFF7A7A68),
    textSubtle: Color(0xFF5A5A48),
    accent: Color(0xFFA2AF9B),
    accentWarm: Color(0xFF8B9A8A),
    accentAmber: Color(0xFFC4956A),
    selected: Color(0xFF3E3E36),
    hover: Color(0xFF484840),
    deletionBg: Color(0xFF3D1F1F),
    deletionBorder: Color(0xFFE53E3E),
    additionBg: Color(0xFF1F3D2A),
    additionBorder: Color(0xFF48BB78),
    warningBg: Color(0xFF3D331F),
    warningText: Color(0xFFF6AD55),
    blockquoteBorder: Color(0xFFA2AF9B),
    textTertiary: Color(0xFF7A7A68),
    success: Color(0xFF48BB78),
    error: Color(0xFFE53E3E),
    onAccent: Color(0xFF141410),
  );
}
