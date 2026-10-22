// 职责: 加载本地打包的官方技能目录与详情。
// 关联文件:
//   lib/shared/services/bundled_official_skills.dart
//   lib/shared/models/official_agent_skill.dart
//   lib/shared/providers/agent_skill_catalog_providers.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//   .agents/rules/error-handling.md
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'bundled_official_skills.dart';
import '../models/official_agent_skill.dart';

export '../models/official_agent_skill.dart';

/// AgentSkillCatalog 域服务。单例,由 Provider 管理生命周期。
///
class AgentSkillCatalogService {
  AgentSkillCatalogService({
    BundledOfficialSkillsLoader officialSkills =
        const BundledOfficialSkillsLoader(),
    AssetBundle? assetBundle,
  }) : _officialSkills = officialSkills,
       _assetBundle = assetBundle;

  final BundledOfficialSkillsLoader _officialSkills;
  final AssetBundle? _assetBundle;

  AssetBundle get _bundle => _assetBundle ?? rootBundle;

  /// 全量官方目录。读本地打包技能，不打网、不分页。
  ///
  /// 目录固定十余条且完全在本地，category/tag 过滤由
  /// `OfficialAgentSkillsNotifier` 在内存里做，这里不再重复一套过滤真源。
  Future<OfficialAgentSkillCatalog> listOfficial() =>
      _officialSkills.list(_bundle);

  /// 官方 AgentSkill 详情。`listingId` 即技能 name。
  Future<OfficialAgentSkill> getOfficial({required String listingId}) =>
      _officialSkills.get(_bundle, listingId);
}
