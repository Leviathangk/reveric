// 职责: 优先展示供应商原始消息，无消息时将 AI 失败映射为本地化文案。
// 关联文件:
//   lib/shared/models/ai_run_failure.dart
//   lib/shared/localization/ark_error_localization.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json

import '../models/ai_run_failure.dart';
import '../utils/ai_error.dart';
import 'ark_error_localization.dart';
import 'locale_keys.dart';

String localizeAiRunFailure(
  AiRunFailure failure,
  String Function(String key) t, {
  bool preferProviderMessage = true,
}) {
  if (preferProviderMessage) {
    final message = tryReadProviderMessage(failure.providerMessage ?? '');
    if (message != null) {
      return message;
    }
  }
  // 本地化兜底只对 provider 失败匹配错误码；本地/流终态保留专用说明。
  if (failure.kind == AiRunFailureKind.http ||
      failure.kind == AiRunFailureKind.streamInterrupted ||
      failure.kind == AiRunFailureKind.requestFailed) {
    final codeKey = arkErrorLocaleKey(
      failure.providerCode,
      failure.providerMessage,
    );
    // 通用参数码没有消息中的上下文长度等具体原因精确。
    final messageKey =
        failure.providerCode?.trim().toLowerCase() == 'invalidparameter'
        ? _providerMessageLocaleKey(failure) ?? codeKey
        : codeKey ?? _providerMessageLocaleKey(failure);
    if (messageKey != null) {
      return t(messageKey);
    }
  }
  final key = switch (failure.kind) {
    AiRunFailureKind.http => _httpFailureLocaleKey(failure),
    AiRunFailureKind.network => LocaleKeys.aiNetworkError,
    AiRunFailureKind.streamInterrupted => LocaleKeys.aiStreamInterrupted,
    AiRunFailureKind.contextWindowExhausted =>
      LocaleKeys.aiContextWindowExhausted,
    AiRunFailureKind.incompleteResponse => LocaleKeys.aiIncompleteResponse,
    AiRunFailureKind.requestFailed => LocaleKeys.aiRequestFailed,
  };
  return t(key);
}

String? _providerMessageLocaleKey(AiRunFailure failure) {
  final message = failure.providerMessage?.trim().toLowerCase();
  if (message == null || message.isEmpty) {
    return null;
  }
  // 供应商余额错误使用明确文案；一般 quota 错误仍交给后面的规则。
  if (message.contains('insufficient credit') ||
      message.contains('credit.insufficient')) {
    return LocaleKeys.aiProviderPaymentRequired;
  }
  for (final (pattern, key) in _providerMessageRules) {
    if (pattern.hasMatch(message)) {
      return key;
    }
  }
  return null;
}

// 顺序具有语义：模型不存在/无权访问的歧义先于明确不存在；
// 上游渠道凭证耗尽先于用户 API Key 错误。规则只输出固定 key，不回显原文。
final _providerMessageRules = <(RegExp, String)>[
  (
    RegExp(r'\bmodel forbidden for user\b|\bmodel\.forbidden\b'),
    LocaleKeys.aiModelForbiddenForUser,
  ),
  (
    RegExp(
      r'\bmodel\b[^\n]{0,160}\bdoes not exist or you do not have access\b|\bdo not have access to (?:the |this )?model\b',
    ),
    LocaleKeys.aiModelMissingOrDenied,
  ),
  (
    RegExp(
      r'\bmodel not found\b|\bmodel_not_found\b|\bmodel\b[^\n]{0,120}\bdoes not exist\b',
    ),
    LocaleKeys.aiModelNotFound,
  ),
  (
    RegExp(r'\bmodel\b[^\n]{0,160}\breached its end of life\b'),
    LocaleKeys.aiModelRetired,
  ),
  (RegExp(r'\bfree promotion has ended\b'), LocaleKeys.aiModelPromotionEnded),
  (
    RegExp(
      r'\bmodel\b[^\n]{0,100}\bis not supported\b|\bmodel\b[^\n]{0,100}\bdoes not support\b|\bthe supported api model names are\b|\bmodel id\b[^\n]{0,160}\bhas no provider supported\b|模型不支持',
    ),
    LocaleKeys.aiModelUnsupported,
  ),
  (
    RegExp(r'\bmodel is unavailable\b'),
    LocaleKeys.aiModelTemporarilyUnavailable,
  ),
  (
    RegExp(
      r'\bmaximum context length\b|\bexceeded model token limit\b|\bprompt is too long\b|\bcontext_length_exceeded\b|\binput token count exceeds the maximum number of tokens allowed\b',
    ),
    LocaleKeys.aiContextWindowExhausted,
  ),
  (
    RegExp(
      r'\bunsupported parameter\b|\binvalid temperature\b|\brange of max_tokens\b|\blevel [^\n]{1,40}not supported, valid levels\b',
    ),
    LocaleKeys.aiRequestParameterUnsupported,
  ),
  (RegExp(r'请打开流式传输'), LocaleKeys.aiStreamingRequired),
  (
    RegExp(r'\bthinking mode must be passed back to the api\b'),
    LocaleKeys.aiThinkingHistoryRequired,
  ),
  (
    RegExp(
      r'\binputimagesensitivecontentdetected\.privacyinformation\b|\binput image\b[^\n]{0,160}\bmay contain real person\b',
    ),
    LocaleKeys.aiInputImagePrivacyRejected,
  ),
  (
    RegExp(
      r'\bgenerated (?:video|image|audio)\b[^\n]{0,80}\bcopyright restrictions\b',
    ),
    LocaleKeys.aiOutputCopyrightRejected,
  ),
  (
    RegExp(
      r'\bsensitive content detected\b|\bsensitive_words_detected\b|\binput may contain sensitive information\b',
    ),
    LocaleKeys.aiContentRejected,
  ),
  (
    RegExp(
      r'\bno available channel\b|无可用渠道|\bno available accounts\b|\bno active api keys available for this group\b|\bno credentials available\b',
    ),
    LocaleKeys.aiProviderChannelUnavailable,
  ),
  (
    RegExp(r'\binsufficient (?:account )?balance\b|预扣费额度失败'),
    LocaleKeys.aiProviderPaymentRequired,
  ),
  (
    RegExp(
      r'\binsufficient_quota\b|\bexceeded your current quota\b|\bbudget pool quota has been exhausted\b|\buser quota is insufficient\b|用户额度不足',
    ),
    LocaleKeys.aiProviderQuotaExceeded,
  ),
  (
    RegExp(
      r'\bconcurrency limit exceeded\b|\brequest queue is full\b|\bsystem protection triggered by request burst\b',
    ),
    LocaleKeys.aiRateLimited,
  ),
  (
    RegExp(r'\bapi key is disabled\b|\bapi key not valid\b'),
    LocaleKeys.aiApiKeyInvalid,
  ),
  (
    RegExp(r'\bservice temporarily overloaded\b'),
    LocaleKeys.aiServiceOverloaded,
  ),
  (
    RegExp(r'\bstream first event timeout\b|\btls handshake timeout\b'),
    LocaleKeys.aiRequestTimeout,
  ),
  (
    RegExp(
      r'\bgetaddrinfo enotfound\b|\ball connection attempts failed\b|\bunexpected_eof_while_reading\b',
    ),
    LocaleKeys.aiProviderConnectionFailed,
  ),
];

String _httpFailureLocaleKey(AiRunFailure failure) {
  return switch (failure.statusCode) {
    400 || 412 || 422 => LocaleKeys.aiBadRequest,
    401 => LocaleKeys.aiApiKeyInvalid,
    402 => LocaleKeys.aiProviderPaymentRequired,
    403 => LocaleKeys.aiAccessDenied,
    404 => LocaleKeys.aiNotFound,
    408 => LocaleKeys.aiRequestTimeout,
    410 => LocaleKeys.aiResourceGone,
    413 => LocaleKeys.aiRequestTooLarge,
    429 => LocaleKeys.aiRateLimited,
    502 || 503 => LocaleKeys.aiServiceOverloaded,
    _ => LocaleKeys.aiRequestFailed,
  };
}
