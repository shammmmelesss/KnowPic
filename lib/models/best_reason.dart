/// AI 推荐「最佳」的理由（文档 8.2：UI 徽章展示，文案由 l10n 提供）
enum BestReason {
  /// 组内只有一张，无从比较
  onlyChoice,

  /// 连拍组：动作最舒展的瞬间
  decisiveMoment,

  /// 多人合影：睁眼/微笑最佳
  bestGroupExpression,

  /// 清晰度最高
  sharpest,

  /// 曝光最好
  bestExposure,

  /// 色彩最好
  bestColor,

  /// 单人表情最好
  bestExpression,

  /// 综合分最高（兜底）
  overallBest,
}
