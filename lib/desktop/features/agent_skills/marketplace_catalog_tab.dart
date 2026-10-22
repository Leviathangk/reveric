// 职责: 展示技能市场尚未接入的占位状态。
// 关联文件:
//   lib/desktop/features/agent_skills/catalog_states.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import 'catalog_states.dart';

class MarketplaceCatalogTab extends StatelessWidget {
  const MarketplaceCatalogTab({super.key});

  @override
  Widget build(BuildContext context) {
    return CatalogEmptyState(
      message: context.t(LocaleKeys.agentSkillMarketNotConnected),
    );
  }
}
