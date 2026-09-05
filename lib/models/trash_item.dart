/// 回收站条目（对应文档 7.6 SafetyService 的 manifest 记录）
class TrashItem {
  TrashItem({
    required this.id,
    required this.originalTitle,
    required this.savedFileName,
    required this.byteSize,
    required this.deletedAt,
    required this.expiresAt,
    this.isLivePhoto = false,
  });

  final String id; // 原相册资产 id
  final String originalTitle;
  final String savedFileName; // 回收站内文件名
  final int byteSize;
  final DateTime deletedAt;
  final DateTime expiresAt; // deletedAt + 30 天
  final bool isLivePhoto;

  int get remainingDays {
    final d = expiresAt.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalTitle': originalTitle,
        'savedFileName': savedFileName,
        'byteSize': byteSize,
        'deletedAt': deletedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'isLivePhoto': isLivePhoto,
      };

  factory TrashItem.fromJson(Map<String, dynamic> json) {
    return TrashItem(
      id: json['id'] as String,
      originalTitle: json['originalTitle'] as String? ?? '',
      savedFileName: json['savedFileName'] as String? ?? '',
      byteSize: json['byteSize'] as int? ?? 0,
      deletedAt: DateTime.tryParse(json['deletedAt'] as String? ?? '') ?? DateTime.now(),
      expiresAt: DateTime.tryParse(json['expiresAt'] as String? ?? '') ??
          DateTime.now().add(const Duration(days: 30)),
      isLivePhoto: json['isLivePhoto'] as bool? ?? false,
    );
  }
}
