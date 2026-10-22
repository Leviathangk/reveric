// 职责: 小说内容搜索面板 — 按 debounced 输入跨章节、设定、角色、物品等内容生成搜索结果。
// 关联文件:
//   lib/desktop/pages/novel_editor.dart
//   lib/shared/database/novel_content_database.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/workspace.json
//   assets/translations/zh-CN/workspace.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../../../shared/components/reveric_checkbox.dart';
import '../../../shared/database/novel_content_database.dart';
import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/models/novel_workspace.dart';
import '../../../shared/theme/theme.dart';

/// 搜索结果数据类
class NovelSearchResult {
  const NovelSearchResult({
    required this.title,
    required this.subtitle,
    required this.section,
    required this.itemId,
    required this.previewSpans,
    this.matchedContent,
  });

  final String title;
  final String subtitle;
  final NovelWorkspaceSection section;
  final String itemId;
  final List<TextSpan> previewSpans;
  final String? matchedContent;
}

/// 搜索范围类型
enum SearchScope {
  chapters,
  worldbuilding,
  outlines,
  materials,
  characters,
  skills,
  items,
  factions,
  creatures,
  foreshadowings,
}

/// 小说内容搜索面板
///
/// 提供全文搜索功能，支持搜索章节、世界观、大纲、素材、人物、技能、物品、阵营、伏笔等内容
class NovelSearchPanel extends HookWidget {
  const NovelSearchPanel({
    super.key,
    required this.searchController,
    required this.searchFocusNode,
    required this.chapters,
    required this.worldbuildingEntries,
    required this.outlineEntries,
    required this.materialEntries,
    required this.characterProfiles,
    required this.skillEntries,
    required this.items,
    required this.factionEntries,
    this.creatureEntries = const <Item>[],
    required this.foreshadowings,
    required this.onResultSelected,
    this.debounceDuration = const Duration(milliseconds: 400),
    this.previewLength = 80,
  });

  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final List<Chapter> chapters;
  final List<Document> worldbuildingEntries;
  final List<Document> outlineEntries;
  final List<Document> materialEntries;
  final List<CharacterProfile> characterProfiles;
  final List<Item> skillEntries;
  final List<Item> items;
  final List<Item> factionEntries;
  final List<Item> creatureEntries;
  final List<Foreshadowing> foreshadowings;
  final ValueSetter<WorkspaceSelection> onResultSelected;
  final Duration debounceDuration;
  final int previewLength;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final chaptersLabel = context.t(LocaleKeys.workspaceChapters);
    final worldbuildingLabel = context.t(LocaleKeys.workspaceLore);
    final outlinesLabel = context.t(LocaleKeys.workspaceOutlines);
    final materialsLabel = context.t(LocaleKeys.workspaceMaterials);
    final charactersLabel = context.t(LocaleKeys.workspaceCharacters);
    final skillsLabel = context.t(LocaleKeys.workspaceSkills);
    final itemsLabel = context.t(LocaleKeys.workspaceItems);
    final factionsLabel = context.t(LocaleKeys.workspaceFactions);
    final creaturesLabel = context.t(LocaleKeys.workspaceCreatures);
    final foreshadowingsLabel = context.t(LocaleKeys.workspaceForeshadowings);

    // 搜索范围状态（默认不搜索章节内容）
    final searchScopes = useState<Set<SearchScope>>({
      SearchScope.worldbuilding,
      SearchScope.outlines,
      SearchScope.materials,
      SearchScope.characters,
      SearchScope.skills,
      SearchScope.items,
      SearchScope.factions,
      SearchScope.creatures,
      SearchScope.foreshadowings,
    });
    final searchValue = useValueListenable(searchController);
    final rawQuery = searchValue.text.trim();
    final debouncedQuery = useDebounced(rawQuery, debounceDuration);

    // 执行搜索
    List<NovelSearchResult> performSearch(String query) {
      if (query.isEmpty) {
        return [];
      }

      final results = <NovelSearchResult>[];
      final lowerQuery = query.toLowerCase();
      final highlightStyle = TextStyle(
        color: colors.accent,
        fontWeight: FontWeight.w600,
        backgroundColor: colors.accent.withValues(alpha: 0.1),
      );
      final normalStyle = TextStyle(color: colors.textSecondary);

      // 搜索章节（如果启用）
      if (searchScopes.value.contains(SearchScope.chapters)) {
        for (final chapter in chapters) {
          final searchText = '${chapter.title ?? ''}\n${chapter.content}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: chapter.title ?? chaptersLabel,
                subtitle: chaptersLabel,
                section: NovelWorkspaceSection.chapters,
                itemId: chapter.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索世界观
      if (searchScopes.value.contains(SearchScope.worldbuilding)) {
        for (final entry in worldbuildingEntries) {
          final searchText = '${entry.title}\n${entry.content}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.title,
                subtitle: worldbuildingLabel,
                section: NovelWorkspaceSection.lore,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索大纲
      if (searchScopes.value.contains(SearchScope.outlines)) {
        for (final entry in outlineEntries) {
          final searchText = '${entry.title}\n${entry.content}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.title,
                subtitle: outlinesLabel,
                section: NovelWorkspaceSection.outlines,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索素材
      if (searchScopes.value.contains(SearchScope.materials)) {
        for (final entry in materialEntries) {
          final searchText = '${entry.title}\n${entry.content}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.title,
                subtitle: materialsLabel,
                section: NovelWorkspaceSection.materials,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索人物
      if (searchScopes.value.contains(SearchScope.characters)) {
        for (final entry in characterProfiles) {
          final searchText = '${entry.name}\n${entry.role}\n${entry.biography}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.name,
                subtitle: charactersLabel,
                section: NovelWorkspaceSection.characters,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索技能
      if (searchScopes.value.contains(SearchScope.skills)) {
        for (final entry in skillEntries) {
          final searchText = '${entry.title}\n${entry.content}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.title,
                subtitle: skillsLabel,
                section: NovelWorkspaceSection.skills,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索物品
      if (searchScopes.value.contains(SearchScope.items)) {
        for (final entry in items) {
          final searchText = '${entry.title}\n${entry.content}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.title,
                subtitle: itemsLabel,
                section: NovelWorkspaceSection.items,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索阵营
      if (searchScopes.value.contains(SearchScope.factions)) {
        for (final entry in factionEntries) {
          final searchText = '${entry.title}\n${entry.content}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.title,
                subtitle: factionsLabel,
                section: NovelWorkspaceSection.factions,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索生物
      if (searchScopes.value.contains(SearchScope.creatures)) {
        for (final entry in creatureEntries) {
          final searchText = '${entry.title}\n${entry.content}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.title,
                subtitle: creaturesLabel,
                section: NovelWorkspaceSection.creatures,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      // 搜索伏笔
      if (searchScopes.value.contains(SearchScope.foreshadowings)) {
        for (final entry in foreshadowings) {
          final searchText = '${entry.title}\n${entry.setup}\n${entry.payoff}';
          final matchResult = _findMatchWithPreview(
            query: lowerQuery,
            content: searchText,
            previewLength: previewLength,
          );
          if (matchResult != null) {
            results.add(
              NovelSearchResult(
                title: entry.title,
                subtitle: foreshadowingsLabel,
                section: NovelWorkspaceSection.foreshadowings,
                itemId: entry.id,
                previewSpans: _buildHighlightSpans(
                  matchResult.preview,
                  lowerQuery,
                  highlightStyle,
                  normalStyle,
                ),
                matchedContent: matchResult.matchedText,
              ),
            );
          }
        }
      }

      return results;
    }

    final effectiveQuery = rawQuery.isEmpty ? '' : debouncedQuery ?? '';
    final results = useMemoized(() => performSearch(effectiveQuery), [
      effectiveQuery,
      searchScopes.value,
      chapters,
      worldbuildingEntries,
      outlineEntries,
      materialEntries,
      characterProfiles,
      skillEntries,
      items,
      factionEntries,
      creatureEntries,
      foreshadowings,
      colors,
      chaptersLabel,
      worldbuildingLabel,
      outlinesLabel,
      materialsLabel,
      charactersLabel,
      skillsLabel,
      itemsLabel,
      factionsLabel,
      creaturesLabel,
      foreshadowingsLabel,
    ]);
    final showLoading =
        rawQuery.isNotEmpty &&
        (debouncedQuery == null || debouncedQuery != rawQuery);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x6l,
        vertical: RevericSpacing.x6l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.workspaceSearchTitle),
            style: _heading(context),
          ),
          const SizedBox(height: RevericSpacing.sm),
          Text(
            context.t(LocaleKeys.workspaceSearchHint),
            style: _description(context),
          ),
          const SizedBox(height: RevericSpacing.x2l),
          _SearchInputField(
            controller: searchController,
            focusNode: searchFocusNode,
            isSearching: showLoading,
          ),
          const SizedBox(height: RevericSpacing.md),
          // 搜索范围选择器（常驻显示）
          _ScopeSelector(
            selectedScopes: searchScopes.value,
            onScopeChanged: (scope, selected) {
              final newScopes = Set<SearchScope>.from(searchScopes.value);
              if (selected) {
                newScopes.add(scope);
              } else {
                newScopes.remove(scope);
              }
              searchScopes.value = newScopes;
            },
          ),
          const SizedBox(height: RevericSpacing.x3l),
          Row(
            children: [
              Text(
                context.t(LocaleKeys.workspaceSearchResults),
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(width: RevericSpacing.sm),
              if (!showLoading)
                Text(
                  context.t(
                    LocaleKeys.workspaceSearchResultsCount,
                    namedArgs: {'count': '${results.length}'},
                  ),
                  style: typo.uiSmall.copyWith(color: colors.textMuted),
                ),
            ],
          ),
          const SizedBox(height: RevericSpacing.lg),
          Expanded(
            child: _buildContent(context, rawQuery, results, showLoading),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    String rawQuery,
    List<NovelSearchResult> results,
    bool isLoading,
  ) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    // 显示 loading 状态
    if (isLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(RevericSpacing.x4l),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RevericRadius.xl),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: RevericSpacing.lg),
            Text(
              context.t(LocaleKeys.workspaceSearchLoading),
              style: typo.ui.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      );
    }

    // 空输入状态
    if (rawQuery.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(RevericSpacing.x4l),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RevericRadius.xl),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Text(
          context.t(LocaleKeys.workspaceSearchIdle),
          style: typo.ui.copyWith(color: colors.textMuted),
        ),
      );
    }

    // 无结果状态
    if (results.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(RevericSpacing.x4l),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RevericRadius.xl),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Text(
          context.t(LocaleKeys.workspaceSearchEmpty),
          style: typo.ui.copyWith(color: colors.textMuted),
        ),
      );
    }

    // 显示搜索结果列表
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: RevericSpacing.md),
      itemBuilder: (context, index) {
        final result = results[index];
        return _SearchResultItem(
          result: result,
          onTap: () => onResultSelected(
            WorkspaceSelection(section: result.section, itemId: result.itemId),
          ),
        );
      },
    );
  }

  /// 查找匹配并生成预览文本
  _MatchResult? _findMatchWithPreview({
    required String query,
    required String content,
    required int previewLength,
  }) {
    if (query.isEmpty) return null;

    final lowerContent = content.toLowerCase();
    final index = lowerContent.indexOf(query);

    if (index == -1) return null;

    // 计算预览范围
    final contextLength = previewLength ~/ 2;
    final start = (index - contextLength).clamp(0, content.length);
    final end = (index + query.length + contextLength).clamp(0, content.length);

    // 提取预览文本
    var preview = content.substring(start, end);

    // 添加省略号
    final hasPrefix = start > 0;
    final hasSuffix = end < content.length;

    // 清理换行符和多余空格
    preview = preview.replaceAll(RegExp(r'\s+'), ' ').trim();

    if (hasPrefix) {
      preview = '...$preview';
    }
    if (hasSuffix) {
      preview = '$preview...';
    }

    // 获取匹配的原始文本（保持原始大小写）
    final matchedText = content.substring(index, index + query.length);

    return _MatchResult(preview: preview, matchedText: matchedText);
  }

  /// 构建高亮文本 spans
  List<TextSpan> _buildHighlightSpans(
    String preview,
    String query,
    TextStyle highlightStyle,
    TextStyle normalStyle,
  ) {
    final spans = <TextSpan>[];
    final lowerPreview = preview.toLowerCase();
    final lowerQuery = query.toLowerCase();

    int start = 0;
    while (true) {
      final matchIndex = lowerPreview.indexOf(lowerQuery, start);
      if (matchIndex == -1) {
        // 添加剩余文本
        if (start < preview.length) {
          spans.add(
            TextSpan(text: preview.substring(start), style: normalStyle),
          );
        }
        break;
      }

      // 添加匹配前的文本
      if (matchIndex > start) {
        spans.add(
          TextSpan(
            text: preview.substring(start, matchIndex),
            style: normalStyle,
          ),
        );
      }

      // 添加高亮匹配的文本（使用预览中的原始大小写）
      spans.add(
        TextSpan(
          text: preview.substring(matchIndex, matchIndex + query.length),
          style: highlightStyle,
        ),
      );

      start = matchIndex + query.length;
    }

    return spans;
  }

  TextStyle _heading(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return typo.heading2.copyWith(color: colors.textPrimary);
  }

  TextStyle _description(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return typo.bodySmall.copyWith(color: colors.textMuted);
  }
}

/// 匹配结果数据类
class _MatchResult {
  const _MatchResult({required this.preview, required this.matchedText});

  final String preview;
  final String matchedText;
}

/// 搜索输入框组件
class _SearchInputField extends StatelessWidget {
  const _SearchInputField({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderInput),
      ),
      padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.lg),
      child: Row(
        children: [
          RevericIcon(
            RevericIcons.search,
            color: colors.textSubtle,
            size: 20,
          ),
          const SizedBox(width: RevericSpacing.sm),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              style: typo.ui.copyWith(color: colors.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: context.t(LocaleKeys.workspaceSearchHint),
                hintStyle: typo.ui.copyWith(color: colors.textSubtle),
              ),
            ),
          ),
          if (isSearching)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                color: colors.accent,
                strokeWidth: 2,
              ),
            )
          else if (controller.text.isNotEmpty)
            IconButton(
              icon: RevericIcon(
                RevericIcons.clear,
                color: colors.textSubtle,
                size: 18,
              ),
              onPressed: () {
                controller.clear();
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
        ],
      ),
    );
  }
}

/// 搜索范围选择器
class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({
    required this.selectedScopes,
    required this.onScopeChanged,
  });

  final Set<SearchScope> selectedScopes;
  final void Function(SearchScope scope, bool selected) onScopeChanged;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Container(
      padding: const EdgeInsets.all(RevericSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t(LocaleKeys.workspaceSearchScopeTitle),
            style: typo.uiSemibold.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.md),
          Wrap(
            spacing: RevericSpacing.md,
            runSpacing: RevericSpacing.sm,
            children: [
              _buildScopeCheckbox(
                context,
                scope: SearchScope.chapters,
                label: context.t(LocaleKeys.workspaceChapters),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.worldbuilding,
                label: context.t(LocaleKeys.workspaceLore),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.outlines,
                label: context.t(LocaleKeys.workspaceOutlines),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.materials,
                label: context.t(LocaleKeys.workspaceMaterials),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.characters,
                label: context.t(LocaleKeys.workspaceCharacters),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.skills,
                label: context.t(LocaleKeys.workspaceSkills),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.items,
                label: context.t(LocaleKeys.workspaceItems),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.factions,
                label: context.t(LocaleKeys.workspaceFactions),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.creatures,
                label: context.t(LocaleKeys.workspaceCreatures),
              ),
              _buildScopeCheckbox(
                context,
                scope: SearchScope.foreshadowings,
                label: context.t(LocaleKeys.workspaceForeshadowings),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScopeCheckbox(
    BuildContext context, {
    required SearchScope scope,
    required String label,
  }) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final isSelected = selectedScopes.contains(scope);

    return InkWell(
      onTap: () => onScopeChanged(scope, !isSelected),
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: RevericSpacing.md,
          vertical: RevericSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.1)
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RevericRadius.medium),
          border: Border.all(
            color: isSelected ? colors.accent : colors.borderSubtle,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: RevericCheckbox(
                value: isSelected,
                onChanged: (value) => onScopeChanged(scope, value),
              ),
            ),
            const SizedBox(width: RevericSpacing.xs),
            Text(
              label,
              style: typo.uiSmall.copyWith(
                color: isSelected ? colors.accent : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索结果项组件
class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({required this.result, required this.onTap});

  final NovelSearchResult result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(RevericRadius.xl),
      child: Ink(
        padding: const EdgeInsets.all(RevericSpacing.x2l),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(RevericRadius.xl),
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.title,
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: RevericSpacing.xs),
            Text(
              result.subtitle,
              style: typo.uiSmall.copyWith(color: colors.textMuted),
            ),
            // 显示匹配内容预览
            if (result.previewSpans.isNotEmpty) ...[
              const SizedBox(height: RevericSpacing.sm),
              RichText(
                text: TextSpan(
                  children: result.previewSpans,
                  style: typo.uiSmall.copyWith(
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
