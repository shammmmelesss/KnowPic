import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 运动与姿态分析（对应文档 Phase 2 P1 动作峰值捕捉）
/// 用于连拍组中识别运动模糊，并估计"决定性瞬间"（清晰 + 姿态舒展）。
class MotionAnalysis {
  const MotionAnalysis({
    required this.motionBlurScore,
    required this.decisiveScore,
  });

  /// 0-1：越高表示单向运动模糊越明显（画面糊）
  final double motionBlurScore;

  /// 0-1：决定性瞬间分数（清晰度 + 姿态舒展度 - 运动模糊惩罚）
  final double decisiveScore;
}

/// 纯 Dart 轻量实现：
/// - 运动模糊：梯度方向高度各向异性（单向拖影）且整体清晰度低 → 疑似运动模糊
/// - 姿态舒展：边缘能量在垂直方向的分布广度（动作幅度大 → 覆盖更多区域）
class MotionAnalyzer {
  MotionAnalyzer._();

  static const int _size = 96;

  static MotionAnalysis analyze(img.Image src) {
    final im = img.copyResize(
      src,
      width: _size,
      height: _size,
      interpolation: img.Interpolation.average,
    );
    final w = im.width;
    final h = im.height;
    final n = w * h;

    final L = Float64List(n);
    for (int i = 0; i < n; i++) {
      final p = im.getPixel(i % w, i ~/ w);
      L[i] = p.getChannel(img.Channel.luminance).toDouble();
    }

    // 梯度 / 拉普拉斯
    final lap = Float64List(n);
    final dirHist = List<double>.filled(8, 0);
    final bandEnergy = List<double>.filled(8, 0);
    double totalGrad = 0;
    double sumLap = 0, sumLap2 = 0;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final xm = x > 0 ? x - 1 : x;
        final xp = x < w - 1 ? x + 1 : x;
        final ym = y > 0 ? y - 1 : y;
        final yp = y < h - 1 ? y + 1 : y;
        final gx = (L[y * w + xp] - L[y * w + xm]) / 2;
        final gy = (L[yp * w + x] - L[ym * w + x]) / 2;
        final mag = math.sqrt(gx * gx + gy * gy);
        final i = y * w + x;
        totalGrad += mag;
        final lapV = L[ym * w + x] + L[yp * w + x] + L[y * w + xm] + L[y * w + xp] - 4 * L[i];
        lap[i] = lapV;
        sumLap += lapV;
        sumLap2 += lapV * lapV;
        if (mag > 0.5) {
          final ang = math.atan2(gy, gx) * 180 / math.pi;
          dirHist[((ang + 180) / 45).floor().clamp(0, 7)] += mag;
        }
        final band = math.min(7, (y * 8) ~/ h);
        bandEnergy[band] += mag;
      }
    }
    final meanLap = sumLap / n;
    final lapVar = math.max(0.0, sumLap2 / n - meanLap * meanLap);
    final sharpness = math.min(1.0, math.sqrt(lapVar) / 28.0);

    // 梯度方向各向异性
    final dirMean = totalGrad == 0 ? 1.0 : totalGrad / 8;
    final dirMax = dirHist.fold(0.0, math.max);
    final dirMaxRatio = dirMean <= 0 ? 1.0 : dirMax / dirMean;
    final anisotropy = ((dirMaxRatio - 1.4) / 2.0).clamp(0.0, 1.0);
    final motionBlur = anisotropy * (1.0 - sharpness * 0.6);

    // 姿态舒展：边缘能量在垂直方向覆盖的广度
    final total = bandEnergy.fold(0.0, (a, b) => a + b);
    int active = 0;
    if (total > 0) {
      final threshold = total * 0.05;
      for (final e in bandEnergy) {
        if (e >= threshold) active++;
      }
    }
    final poseSpread = active / 8.0;

    final decisive = (0.45 * sharpness + 0.35 * poseSpread + 0.20 * (1.0 - motionBlur))
        .clamp(0.0, 1.0)
        .toDouble();
    return MotionAnalysis(
      motionBlurScore: motionBlur.clamp(0.0, 1.0).toDouble(),
      decisiveScore: decisive,
    );
  }
}
