// 职责: 小说全局搜索浮窗 — 订阅工作区内容并承载平台快捷键打开的搜索体验。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/desktop/widgets/workspace/novel_search_panel.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../../shared/database/novel_content_database.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/providers/novel_providers.dart';
import '../../../shared/theme/theme.dart';
import 'novel_search_panel.dart';

const Duration _globalSearchDebounceDuration = Duration(milliseconds: 400);

Future<WorkspaceSelection?> showNovelGlobalSearchOverlay(
  BuildContext context, {
  required String databasePath,
}) {
  return showDialog<WorkspaceSelection>(
    context: context,
    barrierDismissible: true,
    builder: (_) => NovelGlobalSearchOverlay(databasePath: databasePath),
  );
}

class NovelGlobalSearchOverlay extends HookConsumerWidget {
  const NovelGlobalSearchOverlay({super.key, required this.databasePath});

  final String databasePath;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final searchController = useTextEditingController();
    final searchFocusNode = useFocusNode();

    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          searchFocusNode.requestFocus();
        }
      });
      return null;
    }, const []);

    final chaptersAsync = ref.watch(chaptersProvider(databasePath));
    final worldbuildingAsync = ref.watch(
      documentsProvider(path: databasePath, type: documentTypeLore),
    );
    final materialAsync = ref.watch(
      documentsProvider(path: databasePath, type: documentTypeMaterial),
    );
    final charactersAsync = ref.watch(characterProfilesProvider(databasePath));
    final skillsAsync = ref.watch(
      itemsProvider(path: databasePath, type: 'skill'),
    );
    final itemsAsync = ref.watch(
      itemsProvider(path: databasePath, type: 'item'),
    );
    final factionsAsync = ref.watch(
      itemsProvider(path: databasePath, type: 'faction'),
    );
    final creaturesAsync = ref.watch(
      itemsProvider(path: databasePath, type: 'creature'),
    );
    final foreshadowingsAsync = ref.watch(foreshadowingsProvider(databasePath));

    final media = MediaQuery.sizeOf(context);
    final width = (media.width - RevericSpacing.x4l * 2)
        .clamp(360.0, 900.0)
        .toDouble();
    final height = (media.height - RevericSpacing.x4l * 2)
        .clamp(420.0, 760.0)
        .toDouble();

    return Dialog(
      insetPadding: const EdgeInsets.all(RevericSpacing.x2l),
      backgroundColor: Colors.transparent,
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(RevericRadius.large),
            border: Border.all(color: colors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(RevericRadius.large),
            child: NovelSearchPanel(
              searchController: searchController,
              searchFocusNode: searchFocusNode,
              chapters: chaptersAsync.asData?.value ?? const <Chapter>[],
              worldbuildingEntries:
                  worldbuildingAsync.asData?.value ?? const <Document>[],
              outlineEntries: const <Document>[],
              materialEntries:
                  materialAsync.asData?.value ?? const <Document>[],
              characterProfiles:
                  charactersAsync.asData?.value ?? const <CharacterProfile>[],
              skillEntries: skillsAsync.asData?.value ?? const <Item>[],
              items: itemsAsync.asData?.value ?? const <Item>[],
              factionEntries: factionsAsync.asData?.value ?? const <Item>[],
              creatureEntries: creaturesAsync.asData?.value ?? const <Item>[],
              foreshadowings:
                  foreshadowingsAsync.asData?.value ?? const <Foreshadowing>[],
              debounceDuration: _globalSearchDebounceDuration,
              onResultSelected: (selection) {
                Navigator.of(context).pop(selection);
              },
            ),
          ),
        ),
      ),
    );
  }
}
