// 职责: 执行可中止的单次音频 HTTP 请求并统一错误分类和诊断。
// 关联文件:
//   lib/shared/models/audio/request.dart
//   lib/shared/models/audio/exception.dart
//   lib/shared/providers/production_audio.dart
//   lib/shared/services/ai/media_diagnostics.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../../../utils/ai_error.dart';
import '../../../localization/ai_run_failure_localization.dart';
import '../../../logger/app_logger.dart';
import '../../../models/ai_run_failure.dart';
import '../../../models/audio/exception.dart';
import '../../../models/audio/request.dart';
import '../../../models/audio/channels.dart';
import '../../../models/audio/result.dart';
import '../media_diagnostics.dart';
export '../../../models/audio/result.dart';

abstract class AudioClient {
  AudioClient(
    this.client,
    this.apiKey, {
    required this.providerType,
    this.timeout = const Duration(seconds: 150),
  });
  final http.Client client;
  final String apiKey;

  /// 用于查找渠道登记的型号能力和请求默认值。
  final String providerType;
  final Duration timeout;

  /// 渠道未登记的型号没有型号默认值，按协议能解码的输出格式发送。
  AudioRequestDefaults get unlistedModelDefaults;

  Uri get requestUrl;
  Uri submissionUrl(AudioRequest request) => requestUrl;
  Map<String, String> get headers;
  Map<String, dynamic> encode(
    AudioRequest request, {
    List<Uint8List> references = const [],
  });
  AudioGenerationResult decodeResult(Map<String, dynamic> json);
  AudioGenerationResult? decodeBinaryResult(
    Uint8List bytes,
    Map<String, String> headers,
    AudioRequest request,
  ) => null;
  String? providerMessage(Map<String, dynamic> json) =>
      tryReadProviderMessage((message: json));

  Future<AudioGenerationResult> generate(
    AudioRequest request, {
    List<Uint8List> references = const [],
    Future<void>? abortTrigger,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const AudioException('invalid_config');
    }
    // 未登记型号不校验能力，是否允许使用由业务层决定。
    request = lookupAudioChannelModel(providerType, request.modelId) == null
        ? request.withDefaults(unlistedModelDefaults)
        : resolveAudioRequest(providerType, request);
    final endpoint = submissionUrl(request);
    if (!{'http', 'https'}.contains(endpoint.scheme) ||
        endpoint.host.isEmpty ||
        endpoint.userInfo.isNotEmpty ||
        endpoint.hasQuery ||
        endpoint.hasFragment) {
      throw const AudioException('invalid_config');
    }
    final body = encode(request, references: references);
    final abort = Completer<void>();
    var cancelled = false;
    void stop() {
      if (!abort.isCompleted) {
        abort.complete();
      }
    }

    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) {
          cancelled = true;
          stop();
        }),
      );
    }
    int? status;
    String? responseMessage;
    String? diagnosticBody;
    AudioException? httpFailure;
    try {
      // Observe a cancellation that arrived before the transport was created.
      await Future<void>.value();
      if (cancelled) {
        throw const AudioException('cancelled');
      }
      return await (() async {
        final post =
            http.AbortableRequest('POST', endpoint, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers.addAll({...headers, 'Content-Type': 'application/json'})
              ..body = jsonEncode(body);
        final response = await client.send(post);
        status = response.statusCode;
        if (status != 200) {
          // The received status survives an invalid, oversized or stalled body.
          httpFailure = _httpFailure(status!);
        }
        final bytes = <int>[];
        final limit = httpFailure == null ? 32 * 1024 * 1024 : 64 * 1024;
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > limit) {
            throw const FormatException('Audio response too large');
          }
          bytes.addAll(chunk);
        }
        if (httpFailure != null) {
          diagnosticBody = utf8.decode(bytes, allowMalformed: true);
          responseMessage = tryReadProviderMessage((message: diagnosticBody));
          httpFailure = _httpFailure(
            status!,
            responseMessage,
            tryReadProviderErrorCode((message: diagnosticBody)),
          );
          throw httpFailure!;
        }
        final binary = decodeBinaryResult(
          Uint8List.fromList(bytes),
          response.headers,
          request,
        );
        if (binary != null) {
          return binary;
        }
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        responseMessage = providerMessage(json);
        return decodeResult(json);
      })().timeout(
        timeout,
        onTimeout: () {
          stop();
          throw TimeoutException('Audio request timed out', timeout);
        },
      );
    } catch (error) {
      if (cancelled || error is AudioException && error.code == 'cancelled') {
        throw const AudioException('cancelled');
      }
      AppLogger.warning(
        '[AudioClient:$providerType] POST ${endpoint.origin}${endpoint.path} '
        'status=${status ?? "unknown"} type=${error.runtimeType} '
        'error=${safeMediaDiagnostic(error, apiKey)} '
        'message=${safeMediaDiagnostic(responseMessage ?? diagnosticBody ?? error, apiKey)}',
      );
      // Unknown program errors retain their original stack at the task boundary.
      if (error is Error && error is! TypeError) {
        rethrow;
      }
      // No automatic POST retry: a missing receipt cannot prove non-acceptance.
      throw httpFailure ??
          (error is AudioException
              ? error
              : const AudioException('audio_submission_unknown'));
    } finally {
      stop();
    }
  }

  AudioException _httpFailure(
    int status, [
    String? message,
    String? providerCode,
  ]) => AudioException(
    switch (status) {
      401 || 403 => 'authentication',
      429 => 'rate_limited',
      >= 500 => 'unavailable',
      >= 400 && < 500 => 'rejected',
      _ => 'audio_submission_unknown',
    },
    statusCode: status,
    messageKey: localizeAiRunFailure(
      AiRunFailure.http(
        statusCode: status,
        providerMessage: message,
        providerCode: providerCode,
      ),
      (key) => key,
    ),
    detail: providerErrorDetail(providerCode, message, apiKey),
  );
}

/// Temporary outputs are fetched without any provider authentication or POST retry.
Future<Uint8List> downloadAudioOutput(
  Uri url, {
  http.Client? httpClient,
}) async {
  if (url.scheme != 'https' || url.host.isEmpty || url.userInfo.isNotEmpty) {
    throw const AudioException('audio_output_unavailable');
  }
  final client = httpClient ?? http.Client();
  try {
    return await (() async {
      final request = http.Request('GET', url)..followRedirects = false;
      final response = await client.send(request);
      if (response.statusCode != 200) {
        AppLogger.warning(
          '[SeedAudio] output download failed host=${url.host} status=${response.statusCode}',
        );
        await response.stream.drain<void>();
        throw const AudioException('audio_output_unavailable');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > 32 * 1024 * 1024) {
          throw const AudioException('audio_output_unavailable');
        }
        bytes.addAll(chunk);
      }
      return Uint8List.fromList(bytes);
    })().timeout(const Duration(seconds: 60));
  } finally {
    if (httpClient == null) {
      client.close();
    }
  }
}
