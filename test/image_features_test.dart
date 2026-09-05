import 'package:flutter_test/flutter_test.dart';
import 'package:knowpic/core/utils/image_features.dart';
import 'package:image/image.dart' as img;

void main() {
  group('ImageFeatures', () {
    test('特征维度为 128，美学分在 0-10', () {
      final im = img.Image(width: 64, height: 64);
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final v = (x * 255 ~/ 64);
          im.setPixelRgb(x, y, v, v ~/ 2, 255 - v);
        }
      }
      final analysis = ImageFeatures.analyze(im);
      expect(analysis.features.length, ImageFeatures.dim);
      expect(analysis.aestheticScore, inInclusiveRange(0, 10));
      // L1 范数 ≈ 2.0（冷启动常数化）
      var sum = 0.0;
      for (final f in analysis.features) {
        sum += f.abs();
      }
      expect(sum, closeTo(2.0, 1e-3));
      expect(['portrait', 'landscape', 'document', 'food', 'other'],
          contains(analysis.sceneType));
    });

    test('模糊图清晰度分应低于清晰图', () {
      final sharp = img.Image(width: 128, height: 128);
      for (int y = 0; y < 128; y++) {
        for (int x = 0; x < 128; x++) {
          final v = (x * 255 ~/ 128) ^ (y * 7);
          sharp.setPixelRgb(x, y, v, v, v);
        }
      }
      // gaussianBlur 原地修改，需先克隆
      final blur = img.gaussianBlur(img.Image.from(sharp), radius: 3);
      final sharpAnalysis = ImageFeatures.analyze(sharp);
      final blurAnalysis = ImageFeatures.analyze(blur);
      // 清晰度特征：sharp > blur
      expect(sharpAnalysis.features[16], greaterThan(blurAnalysis.features[16]));
      expect(sharpAnalysis.aestheticScore, greaterThan(blurAnalysis.aestheticScore));
    });

    test('人像肤色占比特征', () {
      final im = img.Image(width: 32, height: 32);
      // 一半肤色一半黑
      for (int y = 0; y < 32; y++) {
        for (int x = 0; x < 32; x++) {
          if (x < 16) {
            im.setPixelRgb(x, y, 220, 170, 130); // 肤色
          } else {
            im.setPixelRgb(x, y, 10, 10, 10);
          }
        }
      }
      final analysis = ImageFeatures.analyze(im);
      expect(analysis.sceneType, 'portrait');
      // 肤色占比特征（L1=2.0 归一化后 0.5 占比 → ~0.03）
      expect(analysis.features[20], greaterThan(0.02));
    });
  });
}
