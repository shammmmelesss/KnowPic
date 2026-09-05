import 'dart:math' as math;
import 'dart:typed_data';

/// 向量运算工具（特征点积 / 归一化）
class VectorMath {
  VectorMath._();

  static double dot(Float32List a, List<double> b) {
    double s = 0;
    for (int i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  static double dotList(List<double> a, List<double> b) {
    double s = 0;
    for (int i = 0; i < a.length; i++) {
      s += a[i] * b[i];
    }
    return s;
  }

  static double l1Norm(Float32List a) {
    double s = 0;
    for (final v in a) {
      s += v.abs();
    }
    return s;
  }

  static double l2Norm(Float32List a) {
    double s = 0;
    for (final v in a) {
      s += v * v;
    }
    return math.sqrt(s);
  }

  /// 余弦相似度 [-1, 1]
  static double cosine(Float32List a, Float32List b) {
    final na = l2Norm(a);
    final nb = l2Norm(b);
    if (na == 0 || nb == 0) return 0;
    return dot(a, b) / (na * nb);
  }

  /// 缩放到 L1 范数 = target（用于保持特征尺度稳定，避免用户权重学习时数值漂移）
  static Float32List scaleL1(Float32List a, double target) {
    final norm = l1Norm(a);
    if (norm == 0) return Float32List.fromList(a);
    final factor = target / norm;
    final out = Float32List(a.length);
    for (int i = 0; i < a.length; i++) {
      out[i] = a[i] * factor;
    }
    return out;
  }

  /// sigmoid
  static double sigmoid(double x) {
    if (x >= 0) {
      final z = math.exp(-x);
      return 1.0 / (1.0 + z);
    }
    final z = math.exp(x);
    return z / (1.0 + z);
  }
}
