// 职责: 展示技能市场尚未接入的占位状态。
// 关联文件:
//   lib/mobile/features/agent_skills/tab_states.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/agent_skill.json
//   assets/translations/zh-CN/agent_skill.json
import 'package:flutter/material.dart';

import '../../../shared/localization/app_localization.dart';
import '../../../shared/localization/locale_keys.dart';
import '../../../shared/theme/theme.dart';
import 'tab_states.dart';

class MarketplaceAgentSkillTab extends StatelessWidget {
  const MarketplaceAgentSkillTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SkillTabEmptyState(
      icon: RevericIcons.storefront,
      message: context.t(LocaleKeys.agentSkillMarketNotConnected),
    );
  }
}
