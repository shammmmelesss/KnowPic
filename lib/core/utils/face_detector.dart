import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// 单个人脸候选框（归一化 0-1 坐标）
class FaceBox {
  const FaceBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.eyeOpenScore,
    required this.smileScore,
  });

  final double x, y, w, h;
  final double eyeOpenScore; // 0-1，眼区出现深色瞳孔的估计
  final double smileScore; // 0-1，嘴区饱和度对比（唇色）的估计
}

/// 人脸检测结果（对应文档 Phase 1 P1 基础人脸检测）
/// 用于合影场景的闭眼/微笑检测与"AI 最佳"推荐。
class FaceAnalysis {
  const FaceAnalysis({required this.faces});

  /// 按面积降序排列的人脸候选
  final List<FaceBox> faces;

  int get faceCount => faces.length;

  FaceBox? get largest => faces.isEmpty ? null : faces.first;

  /// 合影最优估计（0-1）：人越多 + 睁眼 + 微笑，越适合作为合影推荐
  double get groupShotScore {
    if (faces.isEmpty) return 0.0;
    final fc = math.min(faces.length, 6);
    final best = faces.first;
    final crowd = 0.15 * fc;
    final quality = 0.45 * best.eyeOpenScore + 0.30 * best.smileScore + 0.10;
    return (crowd + quality).clamp(0.0, 1.0).toDouble();
  }
}

/// 纯 Dart 轻量人脸检测：
/// 肤色连通域 + 面部几何约束（面积/宽高比/填充率），
/// 并对最大人脸做眼区（深色瞳孔）与嘴区（唇色饱和度）启发式评分。
class FaceDetector {
  FaceDetector._();

  static const int _size = 96;

  static FaceAnalysis analyze(img.Image src) {
    final im = img.copyResize(
      src,
      width: _size,
      height: _size,
      interpolation: img.Interpolation.average,
    );
    final w = im.width;
    final h = im.height;
    final n = w * h;

    final skin = Uint8List(n);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        if (_isSkin(p.r / 255.0, p.g / 255.0, p.b / 255.0)) skin[y * w + x] = 1;
      }
    }

    // 连通域（4 邻域 BFS）
    final comp = List<int>.filled(n, -1);
    final minX = <int>[], maxX = <int>[], minY = <int>[], maxY = <int>[], count = <int>[];
    var compId = 0;
    final queue = <int>[];
    for (int i = 0; i < n; i++) {
      if (skin[i] != 1 || comp[i] != -1) continue;
      minX.add(w);
      maxX.add(-1);
      minY.add(h);
      maxY.add(-1);
      count.add(0);
      queue.add(i);
      comp[i] = compId;
      while (queue.isNotEmpty) {
        final c = queue.removeLast();
        final cx = c % w;
        final cy = c ~/ w;
        if (cx < minX[compId]) minX[compId] = cx;
        if (cx > maxX[compId]) maxX[compId] = cx;
        if (cy < minY[compId]) minY[compId] = cy;
        if (cy > maxY[compId]) maxY[compId] = cy;
        count[compId]++;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = cx + dx, ny = cy + dy;
          if (nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
          final ni = ny * w + nx;
          if (skin[ni] == 1 && comp[ni] == -1) {
            comp[ni] = compId;
            queue.add(ni);
          }
        }
      }
      compId++;
    }

    // 几何过滤：面积占比、宽高比、填充率符合人脸形状
    final area = n.toDouble();
    final boxes = <FaceBox>[];
    for (int c = 0; c < compId; c++) {
      final cnt = count[c];
      final areaRatio = cnt / area;
      if (areaRatio < 0.003 || areaRatio > 0.25) continue;
      final bw = maxX[c] - minX[c] + 1;
      final bh = maxY[c] - minY[c] + 1;
      if (bw <= 0 || bh <= 0) continue;
      final aspect = bw / bh;
      if (aspect < 0.30 || aspect > 2.2) continue;
      final fill = cnt / (bw * bh);
      if (fill < 0.25) continue;
      boxes.add(FaceBox(
        x: minX[c] / w,
        y: minY[c] / h,
        w: bw / w,
        h: bh / h,
        eyeOpenScore: 0,
        smileScore: 0,
      ));
    }
    // 面积降序
    boxes.sort((a, b) => (b.w * b.h).compareTo(a.w * a.h));

    // 只对最大人脸做眼/嘴启发式（其余人脸较小，特征不可靠）
    final scored = <FaceBox>[];
    for (int i = 0; i < boxes.length; i++) {
      final b = boxes[i];
      if (i == 0) {
        scored.add(FaceBox(
          x: b.x, y: b.y, w: b.w, h: b.h,
          eyeOpenScore: _eyeOpenScore(im, b),
          smileScore: _smileScore(im, b),
        ));
      } else {
        scored.add(b);
      }
    }
    return FaceAnalysis(faces: scored);
  }

  /// 眼区（y 25%~45%、x 20%~80%）：暗色瞳孔像素占比 → 睁眼估计
  static double _eyeOpenScore(img.Image im, FaceBox b) {
    final x0 = (b.x * im.width + b.w * im.width * 0.20).floor();
    final x1 = (b.x * im.width + b.w * im.width * 0.80).ceil();
    final y0 = (b.y * im.height + b.h * im.height * 0.25).floor();
    final y1 = (b.y * im.height + b.h * im.height * 0.45).ceil();
    if (x1 <= x0 || y1 <= y0) return 0.0;

    // 脸整体平均亮度作为暗部阈值基准
    double faceSum = 0;
    int faceN = 0;
    final fx0 = (b.x * im.width).floor(), fx1 = (b.x * im.width + b.w * im.width).ceil();
    final fy0 = (b.y * im.height).floor(), fy1 = (b.y * im.height + b.h * im.height).ceil();
    for (int y = fy0; y < fy1 && y < im.height; y++) {
      for (int x = fx0; x < fx1 && x < im.width; x++) {
        faceSum += im.getPixel(x, y).getChannel(img.Channel.luminance);
        faceN++;
      }
    }
    if (faceN == 0) return 0.0;
    final faceMean = faceSum / faceN;

    int dark = 0, eyeN = 0;
    for (int y = y0; y < y1 && y < im.height; y++) {
      for (int x = x0; x < x1 && x < im.width; x++) {
        eyeN++;
        if (im.getPixel(x, y).getChannel(img.Channel.luminance) < faceMean - 28) dark++;
      }
    }
    if (eyeN == 0) return 0.0;
    final darkRatio = dark / eyeN;
    // 睁眼：双瞳约 5%~10% 暗像素；闭眼：几乎无
    return ((darkRatio - 0.01) / 0.07).clamp(0.0, 1.0).toDouble();
  }

  /// 嘴区（y 55%~78%、x 25%~75%）：唇色饱和度均值 → 微笑估计
  static double _smileScore(img.Image im, FaceBox b) {
    final x0 = (b.x * im.width + b.w * im.width * 0.25).floor();
    final x1 = (b.x * im.width + b.w * im.width * 0.75).ceil();
    final y0 = (b.y * im.height + b.h * im.height * 0.55).floor();
    final y1 = (b.y * im.height + b.h * im.height * 0.78).ceil();
    if (x1 <= x0 || y1 <= y0) return 0.0;

    double satSum = 0;
    int n = 0;
    for (int y = y0; y < y1 && y < im.height; y++) {
      for (int x = x0; x < x1 && x < im.width; x++) {
        final p = im.getPixel(x, y);
        final r = p.r / 255.0, g = p.g / 255.0, b2 = p.b / 255.0;
        final mx = math.max(r, math.max(g, b2));
        final mn = math.min(r, math.min(g, b2));
        satSum += mx == 0 ? 0.0 : (mx - mn) / mx;
        n++;
      }
    }
    if (n == 0) return 0.0;
    final satMean = satSum / n;
    return ((satMean - 0.08) / 0.12).clamp(0.0, 1.0).toDouble();
  }

  /// 与 ImageFeatures 一致的肤色启发式（归一化 RGB）
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
