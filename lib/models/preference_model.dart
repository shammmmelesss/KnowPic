import 'dart:math' as math;

import '../core/constants.dart';

/// 用户偏好权重模型（对应文档 8.1 主观偏好塔 / 7.5 LearningService）
/// 128 维权重 + 偏置，FTRL-Proximal 在线学习。
class PreferenceModel {
  PreferenceModel({int? dim})
      : dim = dim ?? AppConfig.featureDim,
        weights = List<double>.filled(dim ?? AppConfig.featureDim, 0.5),
        z = List<double>.filled(dim ?? AppConfig.featureDim, 0),
        n = List<double>.filled(dim ?? AppConfig.featureDim, 0),
        bias = 0.0,
        zBias = 0.0,
        nBias = 0.0;

  final int dim;
  List<double> weights; // 当前生效权重（冷启动全 0.5 → 退化为纯 NIMA）
  List<double> z; // FTRL 累积梯度（负）状态
  List<double> n; // FTRL 累积梯度平方和
  double bias;
  double zBias;
  double nBias;

  int sampleCount = 0; // 已训练样本数
  int resetCount = 0; // 重置次数
  DateTime? lastUpdated;
  bool get isTrained => sampleCount > 0;

  /// 计算当前权重（FTRL-Proximal 闭式解）
  void computeWeights() {
    for (int i = 0; i < dim; i++) {
      final zi = z[i];
      if (zi.abs() <= AppConfig.l1) {
        weights[i] = 0.0;
      } else {
        final sigma = (AppConfig.beta + math.sqrt(n[i])) / AppConfig.alpha + AppConfig.l2;
        weights[i] = -(zi - zi.sign * AppConfig.l1) / sigma;
      }
    }
    if (zBias.abs() <= AppConfig.l1) {
      bias = 0.0;
    } else {
      final sigma = (AppConfig.beta + math.sqrt(nBias)) / AppConfig.alpha + AppConfig.l2;
      bias = -(zBias - zBias.sign * AppConfig.l1) / sigma;
    }
  }

  /// 单样本在线更新（逻辑回归梯度）
  void update(List<double> features, double label, double weight) {
    computeWeights();
    // 预测
    double dot = bias;
    for (int i = 0; i < dim; i++) {
      dot += weights[i] * features[i];
    }
    final p = _sigmoid(dot);
    final g = (p - label) * weight; // 梯度系数

    // 更新 z / n（FTRL）
    for (int i = 0; i < dim; i++) {
      final gi = g * features[i];
      final sigma = math.sqrt(n[i] + gi * gi) - math.sqrt(n[i]);
      n[i] += gi * gi;
      z[i] += gi - sigma * weights[i];
    }
    final sigmaBias = math.sqrt(nBias + g * g) - math.sqrt(nBias);
    nBias += g * g;
    zBias += g - sigmaBias * bias;

    sampleCount++;
    lastUpdated = DateTime.now();
    computeWeights();
  }

  /// 成对（BPR 风格）更新：让正样本得分高于负样本
  void updatePair(List<double> positive, List<double> negative, double weight) {
    computeWeights();
    double posScore = bias;
    double negScore = bias;
    for (int i = 0; i < dim; i++) {
      posScore += weights[i] * positive[i];
      negScore += weights[i] * negative[i];
    }
    final diff = posScore - negScore;
    final grad = weight * (1.0 / (1.0 + _exp(-diff))) * -1.0; // -∂logσ(diff)/∂diff

    for (int i = 0; i < dim; i++) {
      final gi = grad * (positive[i] - negative[i]);
      final sigma = math.sqrt(n[i] + gi * gi) - math.sqrt(n[i]);
      n[i] += gi * gi;
      z[i] += gi - sigma * weights[i];
    }
    final sigmaBias = math.sqrt(nBias + grad * grad) - math.sqrt(nBias);
    nBias += grad * grad;
    zBias += grad - sigmaBias * bias;

    sampleCount++;
    lastUpdated = DateTime.now();
    computeWeights();
  }

  /// 重置偏好（反漏斗挽救机制）
  void reset() {
    for (int i = 0; i < dim; i++) {
      weights[i] = 0.5;
      z[i] = 0;
      n[i] = 0;
    }
    bias = 0;
    zBias = 0;
    nBias = 0;
    sampleCount = 0;
    resetCount++;
    lastUpdated = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'dim': dim,
        'weights': weights,
        'z': z,
        'n': n,
        'bias': bias,
        'zBias': zBias,
        'nBias': nBias,
        'sampleCount': sampleCount,
        'resetCount': resetCount,
        'lastUpdated': lastUpdated?.toIso8601String(),
      };

  factory PreferenceModel.fromJson(Map<String, dynamic> json) {
    final dim = json['dim'] as int? ?? AppConfig.featureDim;
    final model = PreferenceModel(dim: dim);
    model.weights = (json['weights'] as List<dynamic>? ?? List.filled(dim, 0.5))
        .map((e) => (e as num).toDouble())
        .toList();
    model.z = (json['z'] as List<dynamic>? ?? List.filled(dim, 0.0))
        .map((e) => (e as num).toDouble())
        .toList();
    model.n = (json['n'] as List<dynamic>? ?? List.filled(dim, 0.0))
        .map((e) => (e as num).toDouble())
        .toList();
    model.bias = (json['bias'] as num?)?.toDouble() ?? 0;
    model.zBias = (json['zBias'] as num?)?.toDouble() ?? 0;
    model.nBias = (json['nBias'] as num?)?.toDouble() ?? 0;
    model.sampleCount = json['sampleCount'] as int? ?? 0;
    model.resetCount = json['resetCount'] as int? ?? 0;
    model.lastUpdated = DateTime.tryParse(json['lastUpdated'] as String? ?? '');
    return model;
  }

  static double _sigmoid(double x) {
    if (x >= 0) {
      final e = _exp(-x);
      return 1.0 / (1.0 + e);
    }
    final e = _exp(x);
    return e / (1.0 + e);
  }

  static double _exp(double x) {
    if (x < -30) return 0.0;
    if (x > 30) return 1.0e13;
    return math.exp(x);
  }
}
