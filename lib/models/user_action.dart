/// 用户行为类型（对应文档 6.2 UserAction / 8.2 学习闭环）
enum ActionType {
  keep, // 显式保留（❤️）
  delete, // 删除
  viewLong, // 停留 >1.5s（正样本）
  viewShort, // 快速划走（负样本）
  zoomIn, // 放大查看（强正样本）
  favorite, // 收藏（强正样本）
}

/// 用户行为样本（隐式/显式反馈）
class UserAction {
  const UserAction({
    required this.assetId,
    required this.groupId,
    required this.type,
    required this.timestamp,
  });

  final String assetId;
  final String groupId;
  final ActionType type;
  final DateTime timestamp;

  /// 行为权重（隐式反馈权重，对应文档 6.2 weight）
  double get weight {
    switch (type) {
      case ActionType.keep:
        return 1.0;
      case ActionType.delete:
        return 1.0;
      case ActionType.viewLong:
        return 0.5;
      case ActionType.viewShort:
        return 0.3;
      case ActionType.zoomIn:
      case ActionType.favorite:
        return 2.0;
    }
  }

  /// 是否为正样本（倾向保留）
  bool get isPositive {
    switch (type) {
      case ActionType.keep:
      case ActionType.viewLong:
      case ActionType.zoomIn:
      case ActionType.favorite:
        return true;
      case ActionType.delete:
      case ActionType.viewShort:
        return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'assetId': assetId,
        'groupId': groupId,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
      };

  factory UserAction.fromJson(Map<String, dynamic> json) {
    return UserAction(
      assetId: json['assetId'] as String,
      groupId: json['groupId'] as String? ?? '',
      type: ActionType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ActionType.viewLong,
      ),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
