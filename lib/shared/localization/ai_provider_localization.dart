// 职责: 将预置 AI Provider 的稳定 id 解析为当前语言的显示名，未知 Provider 保持用户名称。
// 关联文件:
//   lib/shared/models/ai_provider.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/settings.json
//   assets/translations/zh-CN/settings.json
// 遵循的 Rules:
//   .agents/rules/i18n.md

import 'package:flutter/widgets.dart';

import '../models/ai_provider.dart';
import 'app_localization.dart';
import 'locale_keys.dart';

String localizedAiProviderName(BuildContext context, AiProvider provider) {
  return localizedBuiltinAiProviderName(
    context,
    provider.id,
    fallbackName: provider.displayName,
  );
}

String localizedBuiltinAiProviderName(
  BuildContext context,
  String providerId, {
  required String fallbackName,
}) {
  final key = switch (providerId) {
    'deepseek' => LocaleKeys.settingsBuiltinProviderDeepseek,
    'doubao' => LocaleKeys.settingsBuiltinProviderDoubao,
    'moonshot' => LocaleKeys.settingsBuiltinProviderMoonshot,
    'zhipu' => LocaleKeys.settingsBuiltinProviderZhipu,
    'openai' => LocaleKeys.settingsBuiltinProviderOpenai,
    'gemini' => LocaleKeys.settingsBuiltinProviderGemini,
    'anthropic' => LocaleKeys.settingsBuiltinProviderAnthropic,
    'xai' => LocaleKeys.settingsBuiltinProviderXai,
    'qwen' => LocaleKeys.settingsBuiltinProviderQwen,
    'ark' => LocaleKeys.settingsBuiltinProviderArk,
    'debug_deepseek_partial_tool' =>
      LocaleKeys.settingsDebugProviderDeepseekPartialTool,
    'debug_deepseek_truncated' =>
      LocaleKeys.settingsDebugProviderDeepseekTruncated,
    'debug_openai_responses_partial_tool' =>
      LocaleKeys.settingsDebugProviderOpenaiResponsesPartialTool,
    'debug_openai_responses_thinking_only' =>
      LocaleKeys.settingsDebugProviderOpenaiResponsesThinkingOnly,
    _ => null,
  };
  return key == null ? fallbackName : context.t(key);
}
