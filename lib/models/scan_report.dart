import 'group_type.dart';

/// 单次清理报告（对应文档 9.5 清理报告 / 13.2 埋点指标）
class CleanReport {
  CleanReport({
    required this.id,
    required this.createdAt,
    required this.freedBytes,
    required this.deletedCount,
    required this.keptCount,
    required this.groupCount,
    required this.categoryCounts,
  });

  final String id;
  final DateTime createdAt;
  final int freedBytes; // 本次释放的空间
  final int deletedCount;
  final int keptCount;
  final int groupCount;
  final Map<GroupType, int> categoryCounts;

  String get freedLabel => _formatBytes(freedBytes);

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'freedBytes': freedBytes,
        'deletedCount': deletedCount,
        'keptCount': keptCount,
        'groupCount': groupCount,
        'categoryCounts': categoryCounts.map((k, v) => MapEntry(k.name, v)),
      };

  factory CleanReport.fromJson(Map<String, dynamic> json) {
    return CleanReport(
      id: json['id'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      freedBytes: json['freedBytes'] as int? ?? 0,
      deletedCount: json['deletedCount'] as int? ?? 0,
      keptCount: json['keptCount'] as int? ?? 0,
      groupCount: json['groupCount'] as int? ?? 0,
      categoryCounts: (json['categoryCounts'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(GroupType.fromName(k), v as int)),
    );
  }
}

/// 可回收空间预估（分组列表展示）
class ReclaimEstimate {
  const ReclaimEstimate({required this.freedBytes, required this.count});

  final int freedBytes;
  final int count;
}
