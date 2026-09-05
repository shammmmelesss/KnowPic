import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../constants.dart';
import 'vector_math.dart';

/// 单张图片的分析结果：128 维特征 + 客观美学分 + 场景类型
class ImageAnalysis {
  const ImageAnalysis({
    required this.features,
    required this.aestheticScore,
    required this.sceneType,
  });

  final Float32List features;
  final double aestheticScore; // 0-10（NIMA 的轻量替代）
  final String sceneType; // portrait | landscape | document | food | other

  Map<String, dynamic> toJson() => {
        'features': features.toList(),
        'aestheticScore': aestheticScore,
        'sceneType': sceneType,
      };
}

/// 客观特征塔（对应文档 8.1）的纯 Dart 轻量实现：
/// 提取亮度/色彩/清晰度/肤色/构图/纹理共 128 维特征，并缩放到 L1=2.0，
/// 使冷启动时 Features·UserWeights(0.5) 为常数，排序退化为纯 NIMA 分。
class ImageFeatures {
  ImageFeatures._();

  static const int dim = AppConfig.featureDim;
  static const int _gridSize = 64;

  static ImageAnalysis analyze(img.Image src) {
    final im = img.copyResize(
      src,
      width: _gridSize,
      height: _gridSize,
      interpolation: img.Interpolation.average,
    );
    final w = im.width;
    final h = im.height;
    final n = w * h;

    // ---- 网格化基础通道 ----
    final L = Float64List(n); // 亮度 0-255
    final S = Float64List(n); // 饱和度 0-1
    final skin = Uint8List(n);
    final hueDeg = Float64List(n); // 色相 0-360（s>0 时有效）

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        final rn = r / 255.0, gn = g / 255.0, bn = b / 255.0;
        final mx = math.max(rn, math.max(gn, bn));
        final mn = math.min(rn, math.min(gn, bn));
        final i = y * w + x;
        L[i] = r * 0.299 + g * 0.587 + b * 0.114;
        S[i] = mx == 0 ? 0.0 : (mx - mn) / mx;
        if (mx - mn > 1e-6) {
          final d = mx - mn;
          double hh;
          if (mx == rn) {
            hh = 60 * (((gn - bn) / d) % 6);
          } else if (mx == gn) {
            hh = 60 * ((bn - rn) / d + 2);
          } else {
            hh = 60 * ((rn - gn) / d + 4);
          }
          hueDeg[i] = hh < 0 ? hh + 360 : hh;
        }
        if (_isSkin(rn, gn, bn)) skin[i] = 1;
      }
    }

    final f = Float32List(dim);
    var idx = 0;

    // ---- 全局直方图与统计 ----
    final lumHist = List<double>.filled(8, 0);
    final satHist = List<double>.filled(6, 0);
    final hueHist = List<double>.filled(8, 0);
    double satWeightSum = 0;
    double sumL = 0, sumL2 = 0;
    double highlightClip = 0, shadowClip = 0, skinCount = 0;
    for (int i = 0; i < n; i++) {
      final l = L[i] / 255.0;
      final s = S[i];
      sumL += l;
      sumL2 += l * l;
      lumHist[(l * 7.999).floor().clamp(0, 7)] += 1;
      satHist[(s * 5.999).floor().clamp(0, 5)] += 1;
      if (l > 0.92) highlightClip++;
      if (l < 0.08) shadowClip++;
      if (s > 0.2) {
        hueHist[((hueDeg[i] / 360) * 7.999).floor().clamp(0, 7)] += 1;
        satWeightSum += s;
      }
      if (skin[i] == 1) skinCount++;
    }
    final invN = 1.0 / n;
    for (int i = 0; i < 8; i++) {
      f[idx++] = lumHist[i] * invN;
    }
    for (int i = 0; i < 6; i++) {
      f[idx++] = satHist[i] * invN;
    }

    final meanL = sumL / n;
    final contrast = math.min(1.0, math.sqrt(math.max(0.0, sumL2 / n - meanL * meanL)) * 2.0);

    // 梯度 / 拉普拉斯（用于清晰度、边缘方向、纹理）
    final gradMag = Float64List(n);
    final lap = Float64List(n);
    double sumLap = 0, sumLap2 = 0;
    double totalGrad = 0;
    final dirHist = List<double>.filled(8, 0);
    final texHist = List<double>.filled(7, 0);
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
        gradMag[i] = mag;
        totalGrad += mag;
        final lapV = L[ym * w + x] + L[yp * w + x] + L[y * w + xm] + L[y * w + xp] - 4 * L[i];
        lap[i] = lapV;
        sumLap += lapV;
        sumLap2 += lapV * lapV;
        if (mag > 0.5) {
          final ang = math.atan2(gy, gx) * 180 / math.pi; // -180..180
          dirHist[((ang + 180) / 45).floor().clamp(0, 7)] += 1;
          texHist[_logBucket(mag)] += 1;
        }
      }
    }
    final meanLap = sumLap / n;
    final lapVar = math.max(0.0, sumLap2 / n - meanLap * meanLap);
    final sharpness = math.min(1.0, math.sqrt(lapVar) / 28.0);

    f[idx++] = meanL; // 14 平均亮度
    f[idx++] = contrast; // 15 对比度
    f[idx++] = sharpness; // 16 清晰度
    f[idx++] = _colorfulness(im); // 17 色彩丰富度
    f[idx++] = highlightClip * invN; // 18 高光溢出
    f[idx++] = shadowClip * invN; // 19 阴影欠曝
    f[idx++] = skinCount * invN; // 20 肤色占比

    // 21..28 色相直方图（饱和度加权）
    final invSatW = satWeightSum == 0 ? 1.0 : 1.0 / satWeightSum;
    for (int i = 0; i < 8; i++) {
      f[idx++] = hueHist[i] * invSatW;
    }

    // ---- 3x3 网格 8 统计 (29..100) ----
    final cellW = w ~/ 3;
    final cellH = h ~/ 3;
    final cellLuma = List<List<double>>.generate(3, (_) => List<double>.filled(3, 0));
    for (int cy = 0; cy < 3; cy++) {
      for (int cx = 0; cx < 3; cx++) {
        double cSumL = 0, cSumL2 = 0, cSumS = 0, cSkin = 0, cEdge = 0;
        double cR = 0, cB = 0;
        int cCount = 0;
        for (int y = cy * cellH; y < math.min((cy + 1) * cellH, h); y++) {
          for (int x = cx * cellW; x < math.min((cx + 1) * cellW, w); x++) {
            final i = y * w + x;
            final l = L[i] / 255.0;
            cSumL += l;
            cSumL2 += l * l;
            cSumS += S[i];
            cEdge += gradMag[i] / 255.0;
            if (skin[i] == 1) cSkin++;
            final p = im.getPixel(x, y);
            cR += p.r.toDouble() / 255.0;
            cB += p.b.toDouble() / 255.0;
            cCount++;
          }
        }
        if (cCount == 0) cCount = 1;
        final cMeanL = cSumL / cCount;
        final cStd = math.min(1.0, math.sqrt(math.max(0.0, cSumL2 / cCount - cMeanL * cMeanL)) * 2.0);
        cellLuma[cy][cx] = cMeanL;
        f[idx++] = cMeanL;
        f[idx++] = cStd;
        f[idx++] = cSumS / cCount;
        f[idx++] = _cellLapMean(lap, w, h, cx * cellW, cy * cellH, cellW, cellH) / 255.0;
        f[idx++] = cSkin / cCount;
        f[idx++] = cEdge / cCount;
        f[idx++] = cR / cCount;
        f[idx++] = cB / cCount;
      }
    }

    // ---- 101..108 边缘方向直方图 ----
    final invGrad = totalGrad == 0 ? 1.0 : 1.0 / totalGrad;
    for (int i = 0; i < 8; i++) {
      f[idx++] = dirHist[i] * invGrad;
    }

    // ---- 109..112 四象限显著性平衡（构图）----
    final quad = List<double>.filled(4, 0);
    final qc = List<int>.filled(4, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final q = (x < w ~/ 2 ? 0 : 1) + (y < h ~/ 2 ? 0 : 2);
        quad[q] += L[y * w + x] / 255.0;
        qc[q]++;
      }
    }
    for (int i = 0; i < 4; i++) {
      f[idx++] = qc[i] == 0 ? 0 : (quad[i] / qc[i] - meanL).abs();
    }

    // ---- 113..120 垂直 8 带平均亮度 ----
    for (int band = 0; band < 8; band++) {
      final y0 = (band * h) ~/ 8;
      final y1 = ((band + 1) * h) ~/ 8;
      double s = 0;
      for (int y = y0; y < y1; y++) {
        for (int x = 0; x < w; x++) {
          s += L[y * w + x] / 255.0;
        }
      }
      f[idx++] = s / ((y1 - y0) * w);
    }

    // ---- 121..127 纹理粒度直方图 ----
    for (int i = 0; i < 7; i++) {
      f[idx++] = texHist[i] * invGrad;
    }

    assert(idx == dim, 'feature vector dimension mismatch: $idx != $dim');

    // 缩放到 L1 = 2.0，冷启动时 Features·UserWeights(0.5) 恒为 1.0
    final scaled = VectorMath.scaleL1(f, 2.0);
    final score = _aestheticScore(sharpness, highlightClip * invN, shadowClip * invN,
        f[17], _compositionScore(cellLuma, meanL), totalGrad / (n * 255.0));
    final scene = _sceneType(skinCount * invN, f[17], meanL, contrast, im.width, im.height);
    return ImageAnalysis(features: scaled, aestheticScore: score, sceneType: scene);
  }

  static int _logBucket(double mag) {
    if (mag <= 1) return 0;
    if (mag <= 3) return 1;
    if (mag <= 8) return 2;
    if (mag <= 16) return 3;
    if (mag <= 32) return 4;
    if (mag <= 64) return 5;
    return 6;
  }

  static double _cellLapMean(
      Float64List lap, int w, int h, int x0, int y0, int cw, int ch) {
    double s = 0;
    int c = 0;
    for (int y = y0; y < math.min(y0 + ch, h); y++) {
      for (int x = x0; x < math.min(x0 + cw, w); x++) {
        s += lap[y * w + x].abs();
        c++;
      }
    }
    return c == 0 ? 0 : s / c;
  }

  /// 颜色丰富度（Hasler-Süsstrunk）
  static double _colorfulness(img.Image im) {
    double sumRg = 0, sumYb = 0, sumRg2 = 0, sumYb2 = 0;
    final n = im.width * im.height;
    for (int y = 0; y < im.height; y++) {
      for (int x = 0; x < im.width; x++) {
        final p = im.getPixel(x, y);
        final r = p.r.toDouble();
        final g = p.g.toDouble();
        final b = p.b.toDouble();
        final rg = r - g;
        final yb = 0.5 * (r + g) - b;
        sumRg += rg;
        sumYb += yb;
        sumRg2 += rg * rg;
        sumYb2 += yb * yb;
      }
    }
    final meanRg = sumRg / n;
    final meanYb = sumYb / n;
    final stdRg = math.sqrt(math.max(0, sumRg2 / n - meanRg * meanRg));
    final stdYb = math.sqrt(math.max(0, sumYb2 / n - meanYb * meanYb));
    final c = math.sqrt(stdRg * stdRg + stdYb * stdYb) +
        0.3 * math.sqrt(meanRg * meanRg + meanYb * meanYb);
    return math.min(1.0, c / 100.0);
  }

  /// 构图得分：主体靠近三分线交点、亮度显著性适度集中
  static double _compositionScore(List<List<double>> cellLuma, double meanL) {
    const intersections = [(0, 1), (1, 0), (1, 2), (2, 1)];
    double totalDev = 0;
    for (int y = 0; y < 3; y++) {
      for (int x = 0; x < 3; x++) {
        totalDev += (cellLuma[y][x] - meanL).abs();
      }
    }
    if (totalDev < 1e-6) return 0.6; // 均匀画面给中性分
    double interDev = 0;
    for (final (x, y) in intersections) {
      interDev += (cellLuma[y][x] - meanL).abs();
    }
    final focus = interDev / totalDev; // 交点显著性占比
    // 0.4~0.8 区间视为理想构图
    final score = 1.0 - (focus - 0.55).abs() * 2.0;
    return score.clamp(0.0, 1.0).toDouble();
  }

  /// NIMA 的轻量替代：0-10 客观美学分
  static double _aestheticScore(double sharpness, double highlightClip, double shadowClip,
      double colorfulness, double composition, double detail) {
    final exposure = (1.0 - highlightClip * 2.0 - shadowClip * 2.0).clamp(0.0, 1.0);
    final score = 10.0 *
        (0.35 * sharpness +
            0.20 * exposure +
            0.20 * colorfulness +
            0.15 * composition +
            0.10 * math.min(1.0, detail * 6.0));
    return score.clamp(0.0, 10.0).toDouble();
  }

  static String _sceneType(double skinRatio, double colorfulness, double meanL,
      double contrast, int w, int h) {
    if (skinRatio > 0.08) return 'portrait';
    if (w > h * 1.3 || h > w * 1.3) {
      // 竖屏/横屏：根据色彩与对比度粗判
      if (colorfulness > 0.25 && contrast > 0.12) return 'landscape';
      return 'document';
    }
    if (colorfulness > 0.3 && meanL > 0.5) return 'food';
    return 'other';
  }

  /// 肤色启发式（归一化 RGB）
  static bool _isSkin(double r, double g, double b) {
    if (r <= 0.35 || g <= 0.19 || b <= 0.08) return false;
    if (r < g || r < b) return false;
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    if (mx - mn < 0.06) return false;
    if ((r - g).abs() < 0.06) return false;
    return true;
  }
}
