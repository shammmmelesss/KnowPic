import 'group_type.dart';

/// 相似组（对应文档 6.2 SimilarGroup）
class SimilarGroup {
  SimilarGroup({
    required this.groupId,
    required this.type,
    required this.assetIds,
    this.bestId = '',
    this.totalBytes = 0,
    this.representativeTime,
  });

  final String groupId;
  GroupType type;
  List<String> assetIds;
  String bestId; // AI 推荐的"最佳"
  int totalBytes; // 组内照片总大小（用于空间释放预估）
  DateTime? representativeTime;

  bool get isEmpty => assetIds.isEmpty;

  int get size => assetIds.length;

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'type': type.name,
        'assetIds': assetIds,
        'bestId': bestId,
        'totalBytes': totalBytes,
        'representativeTime': representativeTime?.toIso8601String(),
      };

  factory SimilarGroup.fromJson(Map<String, dynamic> json) {
    return SimilarGroup(
      groupId: json['groupId'] as String,
      type: GroupType.fromName(json['type'] as String?),
      assetIds: (json['assetIds'] as List<dynamic>? ?? []).cast<String>(),
      bestId: json['bestId'] as String? ?? '',
      totalBytes: json['totalBytes'] as int? ?? 0,
      representativeTime: DateTime.tryParse(json['representativeTime'] as String? ?? ''),
    );
  }
}
