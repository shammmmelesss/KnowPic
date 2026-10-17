import '../core/constants.dart';
import '../core/utils/vector_math.dart';
import '../models/best_reason.dart';
import '../models/group_type.dart';
import '../models/photo_asset.dart';
import 'learning_service.dart';

/// 排序与推荐（对应文档 7.4 RankingService）
/// FinalScore = 0.4 * BaseNIMA + 0.6 * (Features · UserWeights)
/// 冷启动：UserWeights 全为 0.5，Features 归一化后点积为常数，退化为纯 NIMA 排序。
class RankingService {
  RankingService(this._learning);

  final LearningService _learning;

  /// 计算综合分并排序（降序），返回排序后的列表
  /// 多场景偏好：按组内占主导的场景取独立偏好模型（文档 8.1）
  List<PhotoAsset> sortGroup(List<PhotoAsset> members) {
    if (members.isEmpty) return members;
    final pref = _learning.modelFor(_dominantScene(members));
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

  /// 组内占比最高的场景（多场景偏好路由依据）
  String _dominantScene(List<PhotoAsset> members) {
    final counts = <String, int>{};
    for (final a in members) {
      counts[a.sceneType] = (counts[a.sceneType] ?? 0) + 1;
    }
    String best = AppConfig.sceneOther;
    var bestCount = 0;
    counts.forEach((k, v) {
      if (v > bestCount) {
        bestCount = v;
        best = k;
      }
    });
    return best;
  }

  /// 选出 AI 推荐的"最佳"（FinalScore 最高者）
  String? pickBest(List<PhotoAsset> members) {
    if (members.isEmpty) return null;
    final sorted = sortGroup(members);
    return sorted.first.id;
  }

  /// 推荐理由（对应 UI 徽章"👑 最清晰"等）。
  /// 只返回枚举，文案由 l10n 解析，服务层不掺 UI 语言。
  BestReason bestReason(PhotoAsset best, List<PhotoAsset> members, {GroupType? groupType}) {
    if (members.length < 2) return BestReason.onlyChoice;

    // 连拍组：推荐动作最舒展、最清晰的"决定性瞬间"（文档 Phase 2 动作峰值捕捉）
    if (groupType == GroupType.burst && best.decisiveScore > 0.3) {
      final maxD = members
          .map((a) => a.decisiveScore)
          .reduce((a, b) => a > b ? a : b);
      if (best.decisiveScore >= maxD - 0.05) return BestReason.decisiveMoment;
    }

    // 多人合影：推荐睁眼、微笑最佳的"合影表情最佳"（文档 Phase 1 人脸检测）
    if (members.any((a) => a.faceCount >= 2) && best.faceCount >= 1) {
      final groupScore = 0.45 * best.eyeOpenScore + 0.30 * best.smileScore;
      final bestG = members
          .map((a) => 0.45 * a.eyeOpenScore + 0.30 * a.smileScore)
          .reduce((a, b) => a > b ? a : b);
      if (groupScore >= bestG - 0.05 && groupScore > 0.15) {
        return BestReason.bestGroupExpression;
      }
    }

    final sharps = members.map((a) => a.features[16]).toList()..sort();
    final sharpRank = sharps.indexOf(best.features[16]);
    if (sharpRank >= sharps.length - 1 && best.features[16] > 0.5) {
      return BestReason.sharpest;
    }

    final f = best.features;
    final over = f[18] + f[19]; // 高光+阴影溢出
    final minOver = members.map((a) => a.features[18] + a.features[19]).reduce(
        (a, b) => a < b ? a : b);
    if (over <= minOver + 0.01 && over < 0.05) return BestReason.bestExposure;

    final color = f[17];
    final maxColor = members.map((a) => a.features[17]).reduce((a, b) => a > b ? a : b);
    if (color >= maxColor - 0.02 && color > 0.4) return BestReason.bestColor;

    final skin = f[20];
    if (skin > 0.1) return BestReason.bestExpression;

    return BestReason.overallBest;
  }
}
