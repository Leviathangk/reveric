// 职责: 全局浮窗聊天 UI — 快捷键唤醒 (Cmd/Ctrl+K) + 居中悬浮窗输入框，支持 Agent tool call
// 关联文件:
//   lib/shared/providers/floating_chat_provider.dart
//   lib/shared/services/floating_chat_service.dart
//   lib/shared/theme/theme.dart
//   lib/shared/widgets/ai/tool_activity_group.dart

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:reveric/shared/components/status_animation_clock.dart';
import 'package:reveric/shared/widgets/ai/tool_activity_group.dart';
import 'package:reveric/shared/widgets/stable_selection_area.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../models/ai_message_block.dart';
import '../providers/floating_chat_provider.dart';
import '../theme/theme.dart';
import 'floating_chat_actions.dart';

// 窗口尺寸：按屏幕比例缩放，min/max 限制保证小窗可用、大屏不浪费。
const double _kMinWindowWidth = 320;
const double _kMinWindowHeight = 360;
const double _kMaxWindowWidth = 640;
const double _kMaxWindowHeight = 640;
const double _kPreferredWidthRatio = 0.7;
const double _kPreferredHeightRatio = 0.75;

const double _kEdgeMargin = 16;
const double _kTitleBarHeight = 40;
const Duration _kAnimDuration = Duration(milliseconds: 180);

class GlobalFloatingChat extends HookConsumerWidget {
  const GlobalFloatingChat({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isReady = useState(false);
    final notifier = ref.read(floatingChatProvider.notifier);

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          isReady.value = true;
        }
      });
      return null;
    }, const []);

    useEffect(() {
      bool handleKeyEvent(KeyEvent event) {
        if (event is KeyDownEvent) {
          final isMetaPressed =
              event.logicalKey == LogicalKeyboardKey.meta ||
              HardwareKeyboard.instance.isMetaPressed;
          final isControlPressed =
              event.logicalKey == LogicalKeyboardKey.control ||
              HardwareKeyboard.instance.isControlPressed;
          final isCmdOrCtrl = Platform.isMacOS
              ? isMetaPressed
              : isControlPressed;

          if (isCmdOrCtrl && event.logicalKey == LogicalKeyboardKey.keyK) {
            notifier.toggle();
            return true;
          }
        }
        return false;
      }

      HardwareKeyboard.instance.addHandler(handleKeyEvent);
      return () => HardwareKeyboard.instance.removeHandler(handleKeyEvent);
    }, [notifier]);

    if (!isReady.value) {
      return const SizedBox.shrink();
    }

    // GlobalFloatingChat 与 Navigator 同为外层 Stack 的子节点，自身没有
    // Overlay 祖先，会导致内部 TextField 报 "No Overlay widget found"。
    // 这里提供一层独立 Overlay，让 TextField 选区/工具栏等能正确工作。
    return Positioned.fill(
      child: Overlay(
        initialEntries: [
          OverlayEntry(builder: (context) => const _FloatingChatHost()),
        ],
      ),
    );
  }
}

/// 在 Overlay 内监听打开状态，按需渲染浮窗，避免关闭时仍占用布局/事件。
class _FloatingChatHost extends ConsumerWidget {
  const _FloatingChatHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = ref.watch(floatingChatProvider.select((s) => s.isOpen));
    if (!isOpen) return const SizedBox.shrink();
    return const _FloatingChatWindow();
  }
}

class _FloatingChatWindow extends HookConsumerWidget {
  const _FloatingChatWindow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatState = ref.watch(floatingChatProvider);
    final notifier = ref.read(floatingChatProvider.notifier);
    final colors = RevericTheme.colorsOf(context);
    final textController = useTextEditingController();
    final focusNode = useFocusNode();
    final scrollController = useScrollController();
    final isHovered = useState(false);

    final screenSize = MediaQuery.of(context).size;

    // 自适应窗口尺寸：屏幕比例 × 偏好系数，再用 min/max 与可用空间共同约束。
    final availableWidth = math.max(0.0, screenSize.width - 2 * _kEdgeMargin);
    final availableHeight = math.max(0.0, screenSize.height - 2 * _kEdgeMargin);
    final maxWidth = math.max(
      _kMinWindowWidth,
      math.min(_kMaxWindowWidth, availableWidth),
    );
    final maxHeight = math.max(
      _kMinWindowHeight,
      math.min(_kMaxWindowHeight, availableHeight),
    );
    final windowWidth = (screenSize.width * _kPreferredWidthRatio).clamp(
      _kMinWindowWidth,
      maxWidth,
    );
    final windowHeight = (screenSize.height * _kPreferredHeightRatio).clamp(
      _kMinWindowHeight,
      maxHeight,
    );

    // 位置：首次居中；屏幕/窗口尺寸变化时夹回新边界，保留用户拖动的相对位置。
    final position = useState<Offset?>(null);

    useEffect(() {
      final maxLeft = math.max(
        _kEdgeMargin,
        screenSize.width - windowWidth - _kEdgeMargin,
      );
      final maxTop = math.max(
        _kEdgeMargin,
        screenSize.height - windowHeight - _kEdgeMargin,
      );
      final current = position.value;
      if (current == null) {
        position.value = Offset(
          (screenSize.width - windowWidth) / 2,
          (screenSize.height - windowHeight) / 2,
        );
      } else {
        final clamped = Offset(
          current.dx.clamp(_kEdgeMargin, maxLeft),
          current.dy.clamp(_kEdgeMargin, maxTop),
        );
        if (clamped != current) {
          position.value = clamped;
        }
      }
      return null;
    }, [screenSize, windowWidth, windowHeight]);

    final currentPosition =
        position.value ??
        Offset(
          (screenSize.width - windowWidth) / 2,
          (screenSize.height - windowHeight) / 2,
        );

    void scrollToBottom() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (scrollController.hasClients) {
          scrollController.animateTo(
            scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }

    useEffect(() {
      if (chatState.isStreaming) scrollToBottom();
      return null;
    }, [chatState.messages.length]);

    useEffect(() {
      focusNode.requestFocus();
      return null;
    }, const []);

    void handleSend() {
      final text = textController.text.trim();
      if (text.isEmpty || chatState.isStreaming) return;
      textController.clear();
      notifier.sendMessage(text);
      scrollToBottom();
    }

    return AnimatedPositioned(
      duration: _kAnimDuration,
      curve: Curves.easeOutCubic,
      left: currentPosition.dx,
      top: currentPosition.dy,
      width: windowWidth,
      height: windowHeight,
      child: _FloatingChatWindowContent(
        isHovered: isHovered,
        colors: colors,
        chatState: chatState,
        textController: textController,
        focusNode: focusNode,
        scrollController: scrollController,
        onClose: notifier.close,
        onClear: notifier.clearMessages,
        onSend: handleSend,
        onCancel: notifier.cancel,
        onDragUpdate: (delta) {
          final maxLeft = math.max(
            _kEdgeMargin,
            screenSize.width - windowWidth - _kEdgeMargin,
          );
          final maxTop = math.max(
            _kEdgeMargin,
            screenSize.height - windowHeight - _kEdgeMargin,
          );
          final base = position.value ?? currentPosition;
          position.value = Offset(
            (base.dx + delta.dx).clamp(_kEdgeMargin, maxLeft),
            (base.dy + delta.dy).clamp(_kEdgeMargin, maxTop),
          );
        },
        onDragEnd: () {},
      ),
    );
  }
}

class _ChatTitleBar extends StatelessWidget {
  const _ChatTitleBar({
    required this.hasMessages,
    required this.onClose,
    required this.onClear,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final bool hasMessages;
  final VoidCallback onClose;
  final VoidCallback onClear;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) => onDragUpdate(details.delta),
        onPanEnd: (_) => onDragEnd(),
        child: Container(
          height: _kTitleBarHeight,
          padding: const EdgeInsets.only(
            left: RevericSpacing.lg,
            right: RevericSpacing.xxs,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.surfaceContainer,
                Color.lerp(colors.surfaceContainer, colors.accent, 0.04)!,
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(RevericRadius.small),
                ),
                alignment: Alignment.center,
                child: RevericIcon(
                  RevericIcons.auto_awesome,
                  size: 12,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: RevericSpacing.sm),
              Text(
                context.t(LocaleKeys.floatingChatTitle),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                  letterSpacing: 0.1,
                ),
              ),
              const Spacer(),
              if (hasMessages) FloatingChatActions(onClear: onClear),
              _TitleBarIconButton(
                icon: RevericIcons.close,
                onPressed: onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 窗口内容包装器 - 提供 Overlay 上下文并响应状态变化
class _FloatingChatWindowContent extends HookWidget {
  const _FloatingChatWindowContent({
    required this.isHovered,
    required this.colors,
    required this.chatState,
    required this.textController,
    required this.focusNode,
    required this.scrollController,
    required this.onClose,
    required this.onClear,
    required this.onSend,
    required this.onCancel,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final ValueNotifier<bool> isHovered;
  final RevericColors colors;
  final FloatingChatState chatState;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final VoidCallback onClear;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final controller = useMemoized(() => OverlayPortalController(), const []);

    return OverlayPortal(
      controller: controller,
      overlayChildBuilder: (context) => const SizedBox.shrink(),
      child: MouseRegion(
        onEnter: (_) => isHovered.value = true,
        onExit: (_) => isHovered.value = false,
        child: _FloatingChatContent(
          colors: colors,
          chatState: chatState,
          textController: textController,
          focusNode: focusNode,
          scrollController: scrollController,
          onClose: onClose,
          onClear: onClear,
          onSend: onSend,
          onCancel: onCancel,
          onDragUpdate: onDragUpdate,
          onDragEnd: onDragEnd,
        ),
      ),
    );
  }
}

/// 聊天窗口内容组件 - 提供 Material 和 Overlay 上下文
class _FloatingChatContent extends StatelessWidget {
  const _FloatingChatContent({
    required this.colors,
    required this.chatState,
    required this.textController,
    required this.focusNode,
    required this.scrollController,
    required this.onClose,
    required this.onClear,
    required this.onSend,
    required this.onCancel,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final RevericColors colors;
  final FloatingChatState chatState;
  final TextEditingController textController;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final VoidCallback onClose;
  final VoidCallback onClear;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.canvas,
      borderRadius: BorderRadius.circular(RevericRadius.x2l),
      elevation: 16,
      shadowColor: Colors.black.withAlpha(80),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(RevericRadius.x2l),
        ),
        child: Column(
          children: [
            _ChatTitleBar(
              hasMessages: chatState.messages.isNotEmpty,
              onClose: onClose,
              onClear: onClear,
              onDragUpdate: onDragUpdate,
              onDragEnd: onDragEnd,
            ),
            Divider(height: 1, color: colors.borderSubtle),
            Expanded(
              child: Column(
                children: [
                  Expanded(
                    child: _ChatMessageList(
                      messages: chatState.messages,
                      isStreaming: chatState.isStreaming,
                      scrollController: scrollController,
                      error: chatState.error,
                      isInitialized: chatState.isInitialized,
                    ),
                  ),
                  Divider(height: 1, color: colors.borderSubtle),
                  _ChatInputBar(
                    textController: textController,
                    focusNode: focusNode,
                    isStreaming: chatState.isStreaming,
                    isInitialized: chatState.isInitialized,
                    onSend: onSend,
                    onCancel: onCancel,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleBarIconButton extends StatelessWidget {
  const _TitleBarIconButton({required this.icon, required this.onPressed});

  final String icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return SizedBox(
      width: 26,
      height: 26,
      child: IconButton(
        onPressed: onPressed,
        icon: RevericIcon(icon, size: 14, color: colors.textSecondary),
        padding: EdgeInsets.zero,
        splashRadius: 13,
        hoverColor: colors.surfaceDim,
      ),
    );
  }
}

class _ChatMessageList extends StatelessWidget {
  const _ChatMessageList({
    required this.messages,
    required this.isStreaming,
    required this.scrollController,
    required this.error,
    required this.isInitialized,
  });

  final List<FloatingMessage> messages;
  final bool isStreaming;
  final ScrollController scrollController;
  final String? error;
  final bool isInitialized;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    if (!isInitialized && error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x3l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                RevericIcons.cloud_off,
                size: 28,
                color: colors.textMuted,
              ),
              const SizedBox(height: RevericSpacing.md),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(RevericSpacing.x3l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.accent.withAlpha(20),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: RevericIcon(
                  RevericIcons.auto_awesome,
                  size: 22,
                  color: colors.accent.withAlpha(180),
                ),
              ),
              const SizedBox(height: RevericSpacing.md),
              Text(
                context.t(LocaleKeys.floatingChatEmptyHint),
                style: TextStyle(
                  fontSize: 13,
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: RevericSpacing.xxs),
              Text(
                context.t(LocaleKeys.floatingChatEmptySubHint),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: colors.textSubtle),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.md,
        vertical: RevericSpacing.md,
      ),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isLast = index == messages.length - 1;
        final showLoader =
            isLast &&
            isStreaming &&
            msg.content.isEmpty &&
            !msg.isUser &&
            msg.blocks.isEmpty;

        return Padding(
          padding: EdgeInsets.only(bottom: showLoader ? 4 : RevericSpacing.sm),
          child: _ChatBubble(
            message: msg,
            showStreamingIndicator:
                isLast && isStreaming && msg.content.isNotEmpty && !msg.isUser,
            showPulsing: isLast && isStreaming && !msg.isUser,
          ),
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    this.showStreamingIndicator = false,
    this.showPulsing = false,
  });

  final FloatingMessage message;
  final bool showStreamingIndicator;
  final bool showPulsing;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: isUser ? 260 : double.infinity),
        margin: EdgeInsets.only(left: isUser ? 40 : 0, right: isUser ? 0 : 32),
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.lg,
          vertical: RevericSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isUser ? colors.accent : colors.surfaceDim,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(RevericRadius.medium),
            topRight: const Radius.circular(RevericRadius.medium),
            bottomLeft: Radius.circular(
              isUser ? RevericRadius.medium : RevericRadius.small,
            ),
            bottomRight: Radius.circular(
              isUser ? RevericRadius.small : RevericRadius.medium,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.content.isNotEmpty)
              // 流式期间内容持续增长，禁用选区避免框架选区索引失稳崩溃。
              StableSelectionArea(
                selectable: !showStreamingIndicator,
                child: Text(
                  message.content,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isUser ? colors.surface : colors.textPrimary,
                  ),
                ),
              ),
            // 渲染 tool call blocks
            if (!isUser && message.blocks.isNotEmpty)
              ..._buildToolActivityGroups(
                message.blocks,
                isStreaming: showPulsing,
              ),
            if (showStreamingIndicator)
              Padding(
                padding: const EdgeInsets.only(top: RevericSpacing.xxs),
                child: _StreamingDot(),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildToolActivityGroups(
    List<AiMessageBlock> blocks, {
    required bool isStreaming,
  }) {
    final widgets = <Widget>[];
    final activities = <AiMessageBlock>[];
    var activitiesLastIndex = -1;

    void flushActivities() {
      if (activities.isEmpty) {
        return;
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: RevericSpacing.sm),
          child: AiToolActivityGroup(
            blocks: List<AiMessageBlock>.of(activities),
            // 组内最后一块即整条消息最后一块时，该组的 thinking 仍在增长。
            isStreamingTail:
                isStreaming && activitiesLastIndex == blocks.length - 1,
          ),
        ),
      );
      activities.clear();
      activitiesLastIndex = -1;
    }

    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (block is AiToolCallBlock) {
        activities.add(block);
        activitiesLastIndex = index;
      } else if (block is AiThinkingBlock) {
        // thinking 并入当前活动组，不切组。
        if (block.text.isNotEmpty) {
          activities.add(block);
          activitiesLastIndex = index;
        }
      } else {
        flushActivities();
      }
    }
    flushActivities();
    return widgets;
  }
}

class _StreamingDot extends StatefulWidget {
  const _StreamingDot();

  @override
  State<_StreamingDot> createState() => _StreamingDotState();
}

class _StreamingDotState extends State<_StreamingDot>
    with StatusAnimationClockMixin {
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: const Size.square(6),
        painter: _StreamingDotPainter(
          clock: statusClock,
          animate: statusClockAttached,
          color: RevericTheme.colorsOf(context).accent,
        ),
      ),
    );
  }
}

class _StreamingDotPainter extends CustomPainter {
  _StreamingDotPainter({
    required this.clock,
    required this.animate,
    required this.color,
  }) : super(repaint: animate ? clock : null);

  /// One fade-in plus fade-out, matching an 800ms reverse-repeating pulse.
  static const _cycleSeconds = 1.6;

  final StatusAnimationClock clock;
  final bool animate;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = clock.seconds / _cycleSeconds % 1;
    final value = 1 - (progress * 2 - 1).abs();
    canvas.drawCircle(
      size.center(Offset.zero),
      size.shortestSide / 2,
      Paint()..color = color.withAlpha((150 + value * 105).round()),
    );
  }

  @override
  bool shouldRepaint(_StreamingDotPainter oldDelegate) {
    return oldDelegate.animate != animate || oldDelegate.color != color;
  }
}

class _ChatInputBar extends HookConsumerWidget {
  const _ChatInputBar({
    required this.textController,
    required this.focusNode,
    required this.isStreaming,
    required this.isInitialized,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController textController;
  final FocusNode focusNode;
  final bool isStreaming;
  final bool isInitialized;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final isLoading = !isInitialized;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        RevericSpacing.md,
        RevericSpacing.sm,
        RevericSpacing.md,
        RevericSpacing.md,
      ),
      decoration: BoxDecoration(color: colors.surfaceContainer),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: textController,
              focusNode: focusNode,
              enabled: !isStreaming && isInitialized,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: isLoading
                    ? context.t(LocaleKeys.floatingChatInitializing)
                    : context.t(LocaleKeys.floatingChatPlaceholder),
                hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.lg,
                  vertical: RevericSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.full),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.full),
                  borderSide: BorderSide(color: colors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.full),
                  borderSide: BorderSide(color: colors.accent, width: 1.4),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.full),
                  borderSide: BorderSide(color: colors.borderSubtle),
                ),
                filled: true,
                fillColor: isLoading ? colors.surfaceDim : colors.surface,
                prefixIcon: isLoading
                    ? Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(
                          left: RevericSpacing.md,
                          right: RevericSpacing.sm,
                        ),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.accent,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(width: RevericSpacing.sm),
          _SendStopButton(
            isStreaming: isStreaming,
            isInitialized: isInitialized,
            onSend: onSend,
            onCancel: onCancel,
          ),
        ],
      ),
    );
  }
}

class _SendStopButton extends StatelessWidget {
  const _SendStopButton({
    required this.isStreaming,
    required this.isInitialized,
    required this.onSend,
    required this.onCancel,
  });

  final bool isStreaming;
  final bool isInitialized;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final enabled = isStreaming || isInitialized;
    final bg = enabled ? colors.accent : colors.surfaceDim;
    final fg = enabled ? colors.surface : colors.textMuted;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: InkWell(
        onTap: isStreaming ? onCancel : (isInitialized ? onSend : null),
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        child: SizedBox(
          width: 32,
          height: 32,
          child: RevericIcon(
            isStreaming
                ? RevericIcons.stop_rounded
                : RevericIcons.arrow_upward_rounded,
            size: 16,
            color: fg,
          ),
        ),
      ),
    );
  }
}
