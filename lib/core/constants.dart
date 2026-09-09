/// 全局常量与配置（对应产品文档 5.3 性能目标 / 7.x 接口参数）
class AppConfig {
  AppConfig._();

  // ---- 存储目录与文件 ----
  static const String rootDirName = 'knowpic';
  static const String featuresFile = 'features_128.bin'; // 特征向量池 (float32)
  static const String assetsFile = 'assets.json'; // 资产元数据
  static const String groupsFile = 'groups.json'; // 相似组
  static const String userPrefFile = 'user_pref.json'; // 用户偏好权重
  static const String settingsFile = 'settings.json';
  static const String trashDirName = 'trash'; // 回收站目录
  static const String trashManifestFile = 'manifest.json';
  static const String reportsFile = 'reports.json'; // 清理报告历史

  // ---- 扫描与分析 ----
  static const int thumbnailSize = 256; // 特征分析用缩略图边长（不加载原图）
  static const int thumbnailQuality = 85;
  static const int featureDim = 128; // 特征向量维度
  static const int batchSize = 8; // 批量推理并发数
  static const int scanPageSize = 300; // 相册分页大小
  static const int scanProbeConcurrency = 32; // 本地可用性探测并发数（平台通道调用，串行太慢）

  // ---- 持久化 ----
  static const int storeIsolateThreshold = 1000; // 资产数超过此值时在隔离区编码持久化数据

  // ---- 相似度阈值（汉明距离）----
  static const int hammingThresholdGroup = 12; // 聚类聚合阈值
  static const int hammingThresholdDuplicate = 4; // 完全重复
  static const int hammingThresholdBurst = 10; // 连拍
  static const int hammingThresholdEdit = 12; // 修图稿

  // ---- 分组分类 ----
  static const int burstTimeWindowMs = 3000; // 连拍时间窗
  static const int editHistoryTimeWindowMs = 10 * 60 * 1000; // 修图时间窗
  static const double longShotAspectRatio = 3.0; // 长截图/全景图宽高比
  static const double sizeTolerance = 0.15; // 文件大小容差（重复判定）

  // ---- 回收站 ----
  static const int trashRetentionDays = 30;

  // ---- 偏好学习 (FTRL) ----
  static const double alpha = 0.1;
  static const double beta = 1.0;
  static const double l1 = 0.0;
  static const double l2 = 0.0;
  static const int feedbackFlushThreshold = 200; // 行为队列刷盘阈值
  static const int resetStreakThreshold = 5; // 反漏斗：连续否决 5 组
  static const double positiveViewDuration = 1.5; // 停留 >1.5s → 正样本
  static const double keepWeight = 1.0;
  static const double deleteWeight = 1.0;
  static const double strongPositiveWeight = 2.0; // 放大/收藏 → 强正样本

  // ---- 排序公式：FinalScore = 0.4*NIMA + 0.6*(Features·UserWeights) ----
  static const double objectiveRatio = 0.4;
  static const double personalRatio = 0.6;

  // ---- 多场景偏好（文档 8.1：人像/风景/截图等分别维护独立模型）----
  static const String scenePortrait = 'portrait';
  static const String sceneLandscape = 'landscape';
  static const String sceneDocument = 'document';
  static const String sceneFood = 'food';
  static const String sceneOther = 'other';
  static const String defaultScene = 'all'; // 全局汇总模型（UI 展示/冷启动兜底）
  static const List<String> sceneKeys = [
    scenePortrait,
    sceneLandscape,
    sceneDocument,
    sceneFood,
    sceneOther,
  ];

  /// 场景中文名（设置页展示）
  static String sceneLabel(String scene) {
    switch (scene) {
      case scenePortrait:
        return '人像';
      case sceneLandscape:
        return '风景';
      case sceneDocument:
        return '文档/截图';
      case sceneFood:
        return '美食';
      case sceneOther:
        return '其他';
      case defaultScene:
        return '全局';
      default:
        return scene;
    }
  }

  // ---- 隐式反馈阈值 ----
  static const int viewLongSeconds = 2; // 长停留判定（组详情预览）
}
