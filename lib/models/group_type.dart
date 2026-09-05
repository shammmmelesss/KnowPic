/// 相似组类型（对应文档 6.2 SimilarGroup.type）
enum GroupType {
  burst, // 连拍
  editHistory, // 修图稿
  screenshot, // 截图
  duplicate, // 重复
  longShot, // 长截图/全景
  mixed; // 混合

  String get label {
    switch (this) {
      case GroupType.burst:
        return '连拍组';
      case GroupType.editHistory:
        return '修图稿';
      case GroupType.screenshot:
        return '截图组';
      case GroupType.duplicate:
        return '重复照片';
      case GroupType.longShot:
        return '长图/全景';
      case GroupType.mixed:
        return '相似组';
    }
  }

  static GroupType fromName(String? name) {
    for (final t in GroupType.values) {
      if (t.name == name) return t;
    }
    return GroupType.mixed;
  }
}
