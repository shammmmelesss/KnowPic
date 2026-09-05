import 'package:image/image.dart' as img;

/// 感知哈希工具（对应产品文档 7.2 SimilarityService：dHash 汉明距离）
class PerceptualHash {
  PerceptualHash._();

  /// 计算两个 64 位哈希的汉明距离（不同位数）
  static int hammingDistance(int a, int b) => bitCount(a ^ b);

  /// 64 位整数置位计数（SWAR，避免乘法溢出）
  static int bitCount(int x) {
    x = x - ((x >> 1) & 0x5555555555555555);
    x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
    x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0f;
    x = x + (x >> 8);
    x = x + (x >> 16);
    x = x + (x >> 32);
    return x & 0x7f;
  }

  /// dHash：缩放为 9x8 灰度图，比较相邻像素亮度，产生 64 位哈希
  static int dHash(img.Image src) {
    final g = img.grayscale(img.copyResize(
      src,
      width: 9,
      height: 8,
      interpolation: img.Interpolation.average,
    ));
    int hash = 0;
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        final left = g.getPixel(x, y).getChannelNormalized(img.Channel.luminance);
        final right = g.getPixel(x + 1, y).getChannelNormalized(img.Channel.luminance);
        hash = (hash << 1) | (left < right ? 1 : 0);
      }
    }
    return hash;
  }

  /// aHash：缩放为 8x8 灰度图，与均值比较产生 64 位哈希
  static int aHash(img.Image src) {
    final g = img.grayscale(img.copyResize(src, width: 8, height: 8));
    final values = <double>[];
    double sum = 0;
    for (int y = 0; y < 8; y++) {
      for (int x = 0; x < 8; x++) {
        final v = g.getPixel(x, y).getChannelNormalized(img.Channel.luminance);
        values.add(v.toDouble());
        sum += v;
      }
    }
    final mean = sum / values.length;
    int hash = 0;
    for (final v in values) {
      hash = (hash << 1) | (v > mean ? 1 : 0);
    }
    return hash;
  }
}
