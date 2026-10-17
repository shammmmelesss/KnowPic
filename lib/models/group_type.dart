/// 相似组类型（对应文档 6.2 SimilarGroup.type）
enum GroupType {
  burst, // 连拍
  editHistory, // 修图稿
  screenshot, // 截图
  duplicate, // 重复
  longShot, // 长截图/全景
  mixed; // 混合

  static GroupType fromName(String? name) {
    for (final t in GroupType.values) {
      if (t.name == name) return t;
    }
    return GroupType.mixed;
  }
}
