// 职责: 全局浮窗聊天状态管理 — 消息列表、开关状态、流式响应管理、支持 tool call blocks
// 关联文件:
//   lib/shared/services/floating_chat_service.dart
//   lib/shared/widgets/global_floating_chat.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/models/ai_message_block.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/ai.json
//   assets/translations/zh-CN/ai.json

import 'dart:async';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../localization/ai_run_failure_localization.dart';
import '../models/ai_message_block.dart';
import '../models/ai_provider.dart';
import '../agent/agent_event.dart';
import '../logger/app_logger.dart';
import '../services/floating_chat_service.dart';
import 'novel_providers.dart';
import 'settings_providers.dart';

part 'floating_chat_provider.g.dart';

class FloatingMessage {
  final bool isUser;
  final String content;
  final List<AiMessageBlock> blocks;
  final bool isStreaming;

  const FloatingMessage({
    required this.isUser,
    required this.content,
    this.blocks = const [],
    this.isStreaming = false,
  });

  FloatingMessage copyWith({
    bool? isUser,
    String? content,
    List<AiMessageBlock>? blocks,
    bool? isStreaming,
  }) {
    return FloatingMessage(
      isUser: isUser ?? this.isUser,
      content: content ?? this.content,
      blocks: blocks ?? this.blocks,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}

class FloatingChatState {
  final bool isOpen;
  final bool isStreaming;
  final bool isInitialized;
  final List<FloatingMessage> messages;
  final String? error;

  const FloatingChatState({
    this.isOpen = false,
    this.isStreaming = false,
    this.isInitialized = false,
    this.messages = const [],
    this.error,
  });

  FloatingChatState copyWith({
    bool? isOpen,
    bool? isStreaming,
    bool? isInitialized,
    List<FloatingMessage>? messages,
    Object? error = _sentinel,
  }) {
    return FloatingChatState(
      isOpen: isOpen ?? this.isOpen,
      isStreaming: isStreaming ?? this.isStreaming,
      isInitialized: isInitialized ?? this.isInitialized,
      messages: messages ?? this.messages,
      error: error == _sentinel ? this.error : error as String?,
    );
  }
}

const _sentinel = Object();

final _log = AppLogger.forModule('FloatingChat');

@riverpod
class FloatingChat extends _$FloatingChat {
  FloatingChatService? _service;
  StreamSubscription<AgentEvent>? _subscription;

  @override
  FloatingChatState build() {
    ref.onDispose(() {
      _subscription?.cancel();
      _service?.dispose();
    });
    // 监听 AI 设置变化，当配置改变时重置初始化状态
    ref.listen(aiSettingsProvider, (previous, next) {
      if (previous?.enabledConfigs.length != next.enabledConfigs.length) {
        _service?.dispose();
        _service = null;
        state = state.copyWith(isInitialized: false, isStreaming: false);
      }
    });
    return const FloatingChatState();
  }

  Future<bool> initialize() async {
    if (state.isInitialized) return true;

    final aiSettings = ref.read(aiSettingsProvider);
    final enabledConfigs = aiSettings.enabledConfigs
        .where((provider) => provider.availableModels.isNotEmpty)
        .toList();

    if (enabledConfigs.isEmpty) {
      state = state.copyWith(
        error: 'No AI provider configured. Please configure one in Settings.',
      );
      return false;
    }

    final config = enabledConfigs.first;
    final database = ref.read(appDatabaseProvider);

    _service = FloatingChatService(config: config, database: database);

    try {
      await _service!.initialize();
      state = state.copyWith(isInitialized: true, error: null);
      return true;
    } on Exception catch (e) {
      _log.error('Init error: $e');
      state = state.copyWith(
        error: 'Failed to initialize AI: $e',
        isInitialized: false,
      );
      return false;
    }
  }

  Future<void> sendMessage(String text) async {
    if (state.isStreaming) {
      _log.warning('Cannot send: already streaming');
      return;
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _log.debug('Sending message: $trimmed');

    final initialized = await initialize();
    if (!initialized) {
      _log.error('Failed to initialize');
      return;
    }

    final userMsg = FloatingMessage(isUser: true, content: trimmed);
    final baseMessages = [...state.messages, userMsg];
    state = state.copyWith(
      messages: baseMessages,
      isStreaming: true,
      error: null,
    );
    _log.debug('User message added, total: ${state.messages.length}');

    final buffer = StringBuffer();
    var streamingIndex = -1;

    try {
      final stream = _service!.chatStream(trimmed);
      _subscription?.cancel();
      final completer = Completer<void>();

      _subscription = stream.listen(
        (event) {
          _handleAgentEvent(event, buffer, streamingIndex, (newIndex) {
            streamingIndex = newIndex;
          });
        },
        onError: (Object e) {
          _log.error('Stream error: $e');
          final msgs = List<FloatingMessage>.from(state.messages);
          final content = buffer.isNotEmpty
              ? '$buffer\n\n--- Error: $e ---'
              : 'Error: $e';
          msgs.add(FloatingMessage(isUser: false, content: content));
          state = state.copyWith(
            messages: msgs,
            isStreaming: false,
            error: e.toString(),
          );
          _log.debug('Error handled, messages: ${state.messages.length}');
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          final finalContent = buffer.toString();
          _log.debug('Stream done, content length: ${finalContent.length}');
          if (streamingIndex >= 0) {
            final msgs = List<FloatingMessage>.from(state.messages);
            if (streamingIndex < msgs.length) {
              msgs[streamingIndex] = msgs[streamingIndex].copyWith(
                content: finalContent,
                isStreaming: false,
              );
            }
            state = state.copyWith(messages: msgs);
          }
          state = state.copyWith(isStreaming: false);
          _log.debug('Final messages count: ${state.messages.length}');
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      await completer.future;
    } on Exception catch (e) {
      _log.error('Send error: $e');
      state = state.copyWith(isStreaming: false, error: e.toString());
    }
  }

  void _handleAgentEvent(
    AgentEvent event,
    StringBuffer buffer,
    int streamingIndex,
    void Function(int) onIndexUpdate,
  ) {
    switch (event) {
      case AgentTextDelta(:final text):
        buffer.write(text);
        final currentMessages = state.messages;
        final partial = FloatingMessage(
          isUser: false,
          content: buffer.toString(),
          isStreaming: true,
        );

        if (streamingIndex < 0) {
          onIndexUpdate(currentMessages.length);
          state = state.copyWith(messages: [...currentMessages, partial]);
        } else {
          final msgs = List<FloatingMessage>.from(currentMessages);
          if (streamingIndex < msgs.length) {
            msgs[streamingIndex] = partial;
          }
          state = state.copyWith(messages: msgs);
        }

      case AgentToolCallStart(
        :final callId,
        :final toolName,
        :final arguments,
        :final thoughtSignature,
      ):
        final currentMessages = state.messages;
        final block = AiToolCallBlock(
          id: 'block_$callId',
          callId: callId,
          toolName: toolName,
          arguments: arguments,
          status: AiToolCallStatus.running,
          thoughtSignature: thoughtSignature != null
              ? base64Encode(thoughtSignature)
              : null,
        );

        if (streamingIndex < 0) {
          // 还没有 AI 消息，创建一个带 block 的消息
          onIndexUpdate(currentMessages.length);
          state = state.copyWith(
            messages: [
              ...currentMessages,
              FloatingMessage(
                isUser: false,
                content: buffer.toString(),
                blocks: [block],
                isStreaming: true,
              ),
            ],
          );
        } else {
          // 已有 AI 消息，添加 block
          final msgs = List<FloatingMessage>.from(currentMessages);
          if (streamingIndex < msgs.length) {
            final existingBlocks = List<AiMessageBlock>.from(
              msgs[streamingIndex].blocks,
            );
            // 检查是否已存在相同 callId 的 block
            final existingIndex = existingBlocks.indexWhere(
              (b) => b is AiToolCallBlock && b.callId == callId,
            );
            if (existingIndex >= 0) {
              existingBlocks[existingIndex] = block;
            } else {
              existingBlocks.add(block);
            }
            msgs[streamingIndex] = msgs[streamingIndex].copyWith(
              content: buffer.toString(),
              blocks: existingBlocks,
            );
          }
          state = state.copyWith(messages: msgs);
        }

      case AgentToolCallResult(
        :final callId,
        :final output,
        :final errorMessage,
      ):
        final currentMessages = state.messages;
        if (streamingIndex < 0 || streamingIndex >= currentMessages.length) {
          return;
        }

        final msgs = List<FloatingMessage>.from(currentMessages);
        final msg = msgs[streamingIndex];
        final blocks = List<AiMessageBlock>.from(msg.blocks);
        final blockIndex = blocks.indexWhere(
          (b) => b is AiToolCallBlock && b.callId == callId,
        );

        if (blockIndex >= 0) {
          final existingBlock = blocks[blockIndex] as AiToolCallBlock;
          blocks[blockIndex] = existingBlock.copyWith(
            status: errorMessage == null
                ? AiToolCallStatus.success
                : AiToolCallStatus.error,
            result: output is Map<String, dynamic> ? output : null,
            errorMessage: errorMessage,
          );
          msgs[streamingIndex] = msg.copyWith(blocks: blocks);
          state = state.copyWith(messages: msgs);
        }

      case AgentToolCallIncomplete():
        // 参数未完整生成且尚未 dispatch，只保留日志，不写入浮动聊天记录。
        // 重试事件会清掉 partial 气泡，终态错误由通用提示收口。
        break;

      case AgentToolSkipped(:final callId, :final reason):
        final currentMessages = state.messages;
        if (streamingIndex < 0 || streamingIndex >= currentMessages.length) {
          return;
        }

        final msgs = List<FloatingMessage>.from(currentMessages);
        final msg = msgs[streamingIndex];
        final blocks = List<AiMessageBlock>.from(msg.blocks);
        final blockIndex = blocks.indexWhere(
          (b) => b is AiToolCallBlock && b.callId == callId,
        );

        if (blockIndex >= 0) {
          final existingBlock = blocks[blockIndex] as AiToolCallBlock;
          blocks[blockIndex] = existingBlock.copyWith(
            status: AiToolCallStatus.cancelled,
            errorMessage: reason,
          );
          msgs[streamingIndex] = msg.copyWith(blocks: blocks);
          state = state.copyWith(messages: msgs);
        }

      case AgentError(:final failure):
        final message = localizeAiRunFailure(failure, tr);
        buffer.write('\n\nError: $message');
        final currentMessages = state.messages;
        if (streamingIndex < 0) {
          onIndexUpdate(currentMessages.length);
          state = state.copyWith(
            messages: [
              ...currentMessages,
              FloatingMessage(
                isUser: false,
                content: buffer.toString(),
                isStreaming: false,
              ),
            ],
          );
        } else if (streamingIndex < currentMessages.length) {
          final msgs = List<FloatingMessage>.from(currentMessages);
          msgs[streamingIndex] = msgs[streamingIndex].copyWith(
            content: buffer.toString(),
            isStreaming: false,
          );
          state = state.copyWith(messages: msgs);
        }

      case AgentDone():
      case AgentCancelled():
        // 流结束，在 onDone 中处理
        break;

      case AgentRoundRetry():
        // 重试前清空 partial 气泡（文本 / tool blocks），复用同一气泡承接重试流。
        buffer.clear();
        final currentMessages = state.messages;
        if (streamingIndex >= 0 && streamingIndex < currentMessages.length) {
          final msgs = List<FloatingMessage>.from(currentMessages);
          msgs[streamingIndex] = msgs[streamingIndex].copyWith(
            content: '',
            blocks: const <AiMessageBlock>[],
            isStreaming: true,
          );
          state = state.copyWith(messages: msgs);
        }

      default:
        // 其他事件暂不处理
        break;
    }
  }

  void cancel() {
    _subscription?.cancel();
    _subscription = null;
    _service?.cancel();
    if (state.isStreaming) {
      state = state.copyWith(isStreaming: false);
    }
  }

  void toggle() {
    final newIsOpen = !state.isOpen;
    state = state.copyWith(isOpen: newIsOpen);
    if (newIsOpen) {
      initialize();
    }
  }

  void open() {
    if (!state.isOpen) {
      state = state.copyWith(isOpen: true);
      initialize();
    }
  }

  void close() {
    cancel();
    state = state.copyWith(isOpen: false, isStreaming: false);
  }

  /// 重置状态，用于恢复输入功能
  void reset() {
    _subscription?.cancel();
    _subscription = null;
    state = state.copyWith(isStreaming: false);
  }

  void clearMessages() {
    state = state.copyWith(messages: [], error: null);
  }
}
