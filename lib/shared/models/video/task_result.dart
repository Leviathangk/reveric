// 职责: 表达视频提交回执、上游状态和可安全记录的错误分类。
// 关联文件:
//   lib/shared/services/ai/video/client.dart
//   lib/shared/models/video/request.dart

enum VideoRemoteStatus {
  queued,
  running,
  succeeded,
  failed,
  cancelled,
  expired,
  unknown,
}

enum VideoErrorCode {
  invalid_request,
  configuration_required,
  authentication,
  rejected,
  rate_limited,
  unavailable,
  submission_unknown,
  invalid_response,
  not_found,
}

class VideoException implements Exception {
  const VideoException(
    this.code, {
    this.field,
    this.statusCode,
    this.retryAfter,
    this.messageKey,
    this.detail,
  });
  final VideoErrorCode code;

  /// Controlled field identifier, never an upstream message or signed URL.
  final String? field;
  final int? statusCode;
  final Duration? retryAfter;

  /// Fixed localization key selected by the shared provider error matcher.
  /// Raw provider messages must never reach UI.
  final String? messageKey;

  /// Sanitized provider code and message, persisted for the Agent only.
  final String? detail;

  @override
  String toString() => 'VideoException(${code.name}, $field, HTTP $statusCode)';
}

class VideoSubmission {
  const VideoSubmission({
    required this.taskId,
    required this.modelId,
    required this.pollingUrl,
  });
  final String taskId;

  /// 提交时的型号 ID；部分协议的轮询地址需要它。
  final String modelId;
  final Uri pollingUrl;
}

class VideoTaskResult {
  const VideoTaskResult({
    required this.status,
    this.videoUrl,
    this.messageKey,
    this.detail,
  });
  final VideoRemoteStatus status;
  final Uri? videoUrl;

  /// 已识别的安全本地化键，用于 HTTP 成功但生成任务失败的终态。
  final String? messageKey;

  /// 脱敏后的供应商错误码和原文，只返回给 Agent。
  final String? detail;
}
