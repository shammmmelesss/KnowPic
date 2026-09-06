import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knowpic/core/utils/face_detector.dart';
import 'package:knowpic/core/utils/motion_analysis.dart';

/// 构造纯色背景
img.Image _bg(int size, {int luma = 128}) {
  final im = img.Image(width: size, height: size);
  img.fill(im, color: img.ColorRgb8(luma, luma, luma));
  return im;
}

/// 填充椭圆（image 4.9.2 无 fillEllipse，用椭圆方程逐像素填充）
void _fillEllipse(
  img.Image im, {
  required int cx,
  required int cy,
  required int rx,
  required int ry,
  required img.Color color,
}) {
  for (int y = cy - ry; y <= cy + ry; y++) {
    for (int x = cx - rx; x <= cx + rx; x++) {
      final dx = (x - cx) / rx;
      final dy = (y - cy) / ry;
      if (dx * dx + dy * dy <= 1.0) {
        im.setPixelRgb(x, y, color.r.toInt(), color.g.toInt(), color.b.toInt());
      }
    }
  }
}

/// 构造肤色椭圆人脸，可带眼睛与嘴巴
img.Image _face({bool withEyes = false, bool withMouth = false, int atX = 48}) {
  final im = _bg(96);
  _fillEllipse(
    im,
    cx: atX,
    cy: 45,
    rx: 20,
    ry: 22,
    color: img.ColorRgb8(220, 160, 130),
  );
  if (withEyes) {
    img.fillCircle(
      im,
      x: atX - 12,
      y: 39,
      radius: 3,
      color: img.ColorRgb8(40, 40, 40),
    );
    img.fillCircle(
      im,
      x: atX + 4,
      y: 39,
      radius: 3,
      color: img.ColorRgb8(40, 40, 40),
    );
  }
  if (withMouth) {
    _fillEllipse(
      im,
      cx: atX - 4,
      cy: 55,
      rx: 8,
      ry: 3,
      color: img.ColorRgb8(180, 80, 90),
    );
  }
  return im;
}

void main() {
  group('FaceDetector 人脸检测', () {
    test('纯背景无人脸', () {
      final r = FaceDetector.analyze(_bg(96));
      expect(r.faceCount, 0);
      expect(r.groupShotScore, 0.0);
    });

    test('单张肤色椭圆 → 检测到 1 张人脸', () {
      final r = FaceDetector.analyze(_face());
      expect(r.faceCount, greaterThanOrEqualTo(1));
      expect(r.largest, isNotNull);
    });

    test('两个分开的肤色椭圆 → 检测到 2 张人脸', () {
      final im = _bg(96);
      _fillEllipse(im, cx: 24, cy: 45, rx: 15, ry: 20,
          color: img.ColorRgb8(220, 160, 130));
      _fillEllipse(im, cx: 72, cy: 45, rx: 15, ry: 20,
          color: img.ColorRgb8(220, 160, 130));
      final r = FaceDetector.analyze(im);
      expect(r.faceCount, greaterThanOrEqualTo(2));
    });

    test('有瞳孔的眼区 → 睁眼估计更高', () {
      final withEyes = FaceDetector.analyze(_face(withEyes: true)).largest!;
      final plain = FaceDetector.analyze(_face()).largest!;
      expect(withEyes.eyeOpenScore, greaterThan(plain.eyeOpenScore));
      expect(withEyes.eyeOpenScore, greaterThan(0.3));
    });

    test('多人合影分高于单人', () {
      final im = _bg(96);
      _fillEllipse(im, cx: 24, cy: 45, rx: 15, ry: 20,
          color: img.ColorRgb8(220, 160, 130));
      _fillEllipse(im, cx: 72, cy: 45, rx: 15, ry: 20,
          color: img.ColorRgb8(220, 160, 130));
      final two = FaceDetector.analyze(im);
      final one = FaceDetector.analyze(_face());
      expect(two.groupShotScore, greaterThan(one.groupShotScore));
    });
  });

  group('MotionAnalyzer 动作峰值捕捉', () {
    test('清晰图决定性瞬间分高于模糊图', () {
      final sharp = _checkerboard();
      final blur = img.gaussianBlur(img.Image.from(sharp), radius: 3);
      final s = MotionAnalyzer.analyze(sharp);
      final b = MotionAnalyzer.analyze(blur);
      expect(s.decisiveScore, greaterThan(b.decisiveScore));
    });

    test('单向拖影（水平运动模糊）被识别', () {
      final sharp = _noise();
      final smear = _horizontalSmear(sharp, 7);
      final s = MotionAnalyzer.analyze(sharp);
      final m = MotionAnalyzer.analyze(smear);
      expect(m.motionBlurScore, greaterThan(s.motionBlurScore));
    });
  });
}

/// 4px 棋盘格（高频细节）
img.Image _checkerboard() {
  final im = _bg(96);
  for (int y = 0; y < 96; y++) {
    for (int x = 0; x < 96; x++) {
      final v = (((x ~/ 4) + (y ~/ 4)) % 2 == 0) ? 255 : 0;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return im;
}

/// 确定性伪随机噪声（各向同性高频 → 水平拖影后只剩垂直高频）
img.Image _noise() {
  final im = _bg(96);
  var state = 0x12345678;
  for (int y = 0; y < 96; y++) {
    for (int x = 0; x < 96; x++) {
      state = (state * 1103515245 + 12345) & 0x7fffffff;
      final v = state % 256;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return im;
}

/// 水平滑动平均 → 单向运动模糊
img.Image _horizontalSmear(img.Image src, int halfWindow) {
  final im = _bg(src.width);
  for (int y = 0; y < src.height; y++) {
    for (int x = 0; x < src.width; x++) {
      var sum = 0;
      var cnt = 0;
      for (int k = -halfWindow; k <= halfWindow; k++) {
        final nx = x + k;
        if (nx < 0 || nx >= src.width) continue;
        sum += src.getPixel(nx, y).getChannel(img.Channel.luminance).toInt();
        cnt++;
      }
      final v = (sum / cnt).round();
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return im;
}
