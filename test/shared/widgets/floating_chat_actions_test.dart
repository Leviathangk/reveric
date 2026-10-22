// 职责: 验证浮窗清空聊天先经菜单和确认，取消时保留消息。
// 关联文件:
//   lib/shared/widgets/floating_chat_actions.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/floating_chat.json
//   assets/translations/zh-CN/floating_chat.json
//   assets/translations/en/common.json
//   assets/translations/zh-CN/common.json

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:reveric/shared/widgets/floating_chat_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });
  setUp(() => rootBundle.clear());

  testWidgets(
    'clear requires confirmation and cancellation preserves messages',
    (tester) async {
      final messages = ['Keep this message'];
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en')],
          path: 'assets/translations',
          assetLoader: const MergingAssetLoader(),
          startLocale: const Locale('en'),
          fallbackLocale: const Locale('en'),
          child: Builder(
            builder: (context) => MaterialApp(
              localizationsDelegates: context.localizationDelegates,
              supportedLocales: context.supportedLocales,
              locale: context.locale,
              theme: RevericThemeData.reveric.toThemeData(),
              home: const Scaffold(body: Text('App page')),
              // Match MaterialApp.builder: the floating overlay is a sibling
              // of the app Navigator, not a descendant of its routes.
              builder: (context, child) => RevericTheme(
                data: RevericThemeData.reveric,
                child: Stack(
                  children: [
                    child!,
                    Positioned.fill(
                      child: Overlay(
                        initialEntries: [
                          OverlayEntry(
                            builder: (context) => Align(
                              alignment: Alignment.topLeft,
                              child: Material(
                                child: FloatingChatActions(
                                  onClear: messages.clear,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Clear conversation'), findsNothing);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear conversation'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(messages, ['Keep this message']);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(messages, ['Keep this message']);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Clear conversation'));
      await tester.pumpAndSettle();
      expect(messages, isEmpty);
    },
  );
}
