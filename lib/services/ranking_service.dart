import '../core/constants.dart';
import '../core/utils/vector_math.dart';
import '../models/photo_asset.dart';
import 'learning_service.dart';

/// 排序与推荐（对应文档 7.4 RankingService）
/// FinalScore = 0.4 * BaseNIMA + 0.6 * (Features · UserWeights)
/// 冷启动：UserWeights 全为 0.5，Features 归一化后点积为常数，退化为纯 NIMA 排序。
class RankingService {
  RankingService(this._learning);

  final LearningService _learning;

  /// 计算综合分并排序（降序），返回排序后的列表
  List<PhotoAsset> sortGroup(List<PhotoAsset> members) {
    final pref = _learning.model;
    final trained = pref.isTrained;
    for (final a in members) {
      double personal = 0;
      if (trained) {
        personal = VectorMath.dot(a.features, pref.weights) + pref.bias;
      } else {
        // 冷启动：点积为常数 1.0（Features L1=2，权重全 0.5）
        personal = 1.0;
      }
      a.finalScore =
          AppConfig.objectiveRatio * a.baseScore + AppConfig.personalRatio * personal;
    }
    members.sort((a, b) => b.finalScore.compareTo(a.finalScore));
    return members;
  }

  /// 选出 AI 推荐的"最佳"（FinalScore 最高者）
  String? pickBest(List<PhotoAsset> members) {
    if (members.isEmpty) return null;
    final sorted = sortGroup(members);
    return sorted.first.id;
  }

  /// 推荐理由（对应 UI 徽章"👑 最清晰"等）
  String bestReason(PhotoAsset best, List<PhotoAsset> members) {
    if (members.length < 2) return '唯一选择';
    final sharps = members.map((a) => a.features[16]).toList()..sort();
    final sharpRank = sharps.indexOf(best.features[16]);
    if (sharpRank >= sharps.length - 1 && best.features[16] > 0.5) return '最清晰';

    final f = best.features;
    final over = f[18] + f[19]; // 高光+阴影溢出
    final minOver = members.map((a) => a.features[18] + a.features[19]).reduce(
        (a, b) => a < b ? a : b);
    if (over <= minOver + 0.01 && over < 0.05) return '曝光最佳';

    final color = f[17];
    final maxColor = members.map((a) => a.features[17]).reduce((a, b) => a > b ? a : b);
    if (color >= maxColor - 0.02 && color > 0.4) return '色彩最佳';

    final skin = f[20];
    if (skin > 0.1) return '表情最佳';

    return '综合最佳';
  }
}
