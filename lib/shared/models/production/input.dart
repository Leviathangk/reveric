// 职责: 保存制作片段的有序参考身份、来源和用途，不复制来源文件信息。
// 关联文件:
//   lib/shared/database/novel_content_database.dart
//   lib/shared/services/production/canvas_service.dart
//   lib/shared/models/video/request.dart
import '../../utils/short_entity_id.dart';
import '../video/request.dart';

enum ProductionInputType { asset, node }

class ProductionInput {
  const ProductionInput({
    required this.id,
    required this.refType,
    required this.refId,
    required this.role,
  });

  factory ProductionInput.asset(String assetId, VideoInputRole role) =>
      ProductionInput(
        id: buildShortEntityId(ShortEntityIdType.productionInput),
        refType: ProductionInputType.asset,
        refId: assetId,
        role: role,
      );

  factory ProductionInput.node(String nodeId, VideoInputRole role) =>
      ProductionInput(
        id: buildShortEntityId(ShortEntityIdType.productionInput),
        refType: ProductionInputType.node,
        refId: nodeId,
        role: role,
      );

  final String id;
  final ProductionInputType refType;
  final String refId;
  final VideoInputRole role;

  String get identity => id;
  String get sourceIdentity => '${refType.name}:$refId:${role.name}';
  String? get sourceNodeId =>
      refType == ProductionInputType.node ? refId : null;

  ProductionInput withRole(VideoInputRole value) =>
      ProductionInput(id: id, refType: refType, refId: refId, role: value);

  Map<String, dynamic> toJson() => {
    'id': id,
    'ref_type': refType.name,
    'ref_id': refId,
    'role': role.name,
  };

  factory ProductionInput.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final refId = json['ref_id'] as String;
    if (id.trim().isEmpty || refId.trim().isEmpty) {
      throw const FormatException('Production input identity is required');
    }
    return ProductionInput(
      id: id,
      refType: ProductionInputType.values.byName(json['ref_type'] as String),
      refId: refId,
      role: VideoInputRole.values.byName(json['role'] as String),
    );
  }

  static void validateList(List<ProductionInput> inputs) {
    if (inputs.map((i) => i.id).toSet().length != inputs.length ||
        inputs.map((i) => i.sourceIdentity).toSet().length != inputs.length) {
      throw const FormatException('Duplicate production input');
    }
  }
}
