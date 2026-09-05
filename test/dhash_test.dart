import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knowpic/core/utils/dhash.dart';

void main() {
  group('PerceptualHash', () {
    test('hammingDistance 计算正确', () {
      expect(PerceptualHash.hammingDistance(0, 0), 0);
      expect(PerceptualHash.hammingDistance(0x0A, 0x0F), 2);
      expect(PerceptualHash.hammingDistance(0xFFFFFFFFFFFFFFFF, 0), 64);
      expect(PerceptualHash.bitCount(0xF0F0F0F0F0F0F0F0), 32);
    });

    test('相同图像哈希一致', () {
      final a = img.Image(width: 32, height: 32);
      img.fill(a, color: img.ColorRgb8(120, 120, 120));
      final b = img.Image(width: 32, height: 32);
      img.fill(b, color: img.ColorRgb8(120, 120, 120));
      expect(PerceptualHash.dHash(a), PerceptualHash.dHash(b));
    });

    test('不同亮度图像哈希距离小（内容相同）', () {
      final dark = img.Image(width: 64, height: 64);
      img.fill(dark, color: img.ColorRgb8(60, 60, 60));
      final light = img.Image(width: 64, height: 64);
      img.fill(light, color: img.ColorRgb8(200, 200, 200));
      // 纯色图 dHash 全为 0，距离应为 0
      expect(PerceptualHash.hammingDistance(
          PerceptualHash.dHash(dark), PerceptualHash.dHash(light)), 0);
    });

    test('明显不同图像哈希距离大', () {
      // 从左到右渐亮（dHash 每位都为 1）vs 均匀灰（dHash 全 0）
      final left = img.Image(width: 64, height: 64);
      for (int y = 0; y < 64; y++) {
        for (int x = 0; x < 64; x++) {
          final v = x * 255 ~/ 63;
          left.setPixelRgb(x, y, v, v, v);
        }
      }
      final right = img.Image(width: 64, height: 64);
      img.fill(right, color: img.ColorRgb8(128, 128, 128));
      final d = PerceptualHash.hammingDistance(
          PerceptualHash.dHash(left), PerceptualHash.dHash(right));
      expect(d, greaterThan(20));
    });
  });
}
