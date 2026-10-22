// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'floating_chat_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FloatingChat)
final floatingChatProvider = FloatingChatProvider._();

final class FloatingChatProvider
    extends $NotifierProvider<FloatingChat, FloatingChatState> {
  FloatingChatProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'floatingChatProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$floatingChatHash();

  @$internal
  @override
  FloatingChat create() => FloatingChat();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FloatingChatState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FloatingChatState>(value),
    );
  }
}

String _$floatingChatHash() => r'4f8116e23c64d6d9c67b71d4e8c7794dd6d6359c';

abstract class _$FloatingChat extends $Notifier<FloatingChatState> {
  FloatingChatState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<FloatingChatState, FloatingChatState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<FloatingChatState, FloatingChatState>,
              FloatingChatState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
