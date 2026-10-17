// 生成 KnowPic App Icon 全套尺寸（占位品牌图标，可随时替换）
// 用法：dart run tool/gen_app_icon.dart
import 'dart:io';

import 'package:image/image.dart' as img;

const int base = 1024;

void main() {
  final icon = _render(base);
  final dir = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');

  const targets = <String, int>{
    'Icon-App-20x20@1x.png': 20,
    'Icon-App-20x20@2x.png': 40,
    'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29,
    'Icon-App-29x29@2x.png': 58,
    'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40,
    'Icon-App-40x40@2x.png': 80,
    'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120,
    'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76,
    'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };

  for (final entry in targets.entries) {
    final resized = img.copyResize(
      icon,
      width: entry.value,
      height: entry.value,
      interpolation: img.Interpolation.cubic,
    );
    File('${dir.path}/${entry.key}')
        .writeAsBytesSync(img.encodePng(resized, level: 6));
  }
  stdout.writeln('生成 ${targets.length} 个图标 -> ${dir.path}');
}

img.Image _render(int size) {
  final image = img.Image(width: size, height: size, numChannels: 3);

  // 背景渐变（靛蓝 -> 亮蓝）
  final top = img.ColorRgb8(0x3A, 0x3C, 0xA6);
  final bottom = img.ColorRgb8(0x2C, 0x7A, 0xD6);
  for (var y = 0; y < size; y++) {
    final t = y / (size - 1);
    final c = img.ColorRgb8(
      (top.r + (bottom.r - top.r) * t).round(),
      (top.g + (bottom.g - top.g) * t).round(),
      (top.b + (bottom.b - top.b) * t).round(),
    );
    img.fillRect(image, x1: 0, y1: y, x2: size, y2: y + 1, color: c);
  }

  // 后层照片（浅色，暗示“相似重复照片”堆叠）
  final back = _rect(size, left: 0.30, top: 0.16, side: 0.58);
  img.fillRect(
    image,
    x1: back.$1,
    y1: back.$2,
    x2: back.$1 + back.$3,
    y2: back.$2 + back.$3,
    color: img.ColorRgb8(0x9A, 0xB4, 0xE3),
  );

  // 主照片卡片
  final card = _rect(size, left: 0.17, top: 0.28, side: 0.58);
  img.fillRect(
    image,
    x1: card.$1,
    y1: card.$2,
    x2: card.$1 + card.$3,
    y2: card.$2 + card.$3,
    color: img.ColorRgb8(255, 255, 255),
  );

  // 山（三角）
  final cx = card.$1 + (card.$3 * 0.5).round();
  final baseY = card.$2 + (card.$3 * 0.78).round();
  final peakY = card.$2 + (card.$3 * 0.30).round();
  final half = (card.$3 * 0.32).round();
  img.fillPolygon(
    image,
    vertices: <img.Point>[
      img.Point(cx - half, baseY),
      img.Point(cx + half, baseY),
      img.Point(cx, peakY),
    ],
    color: img.ColorRgb8(0x2C, 0x7A, 0xD6),
  );

  // 太阳
  img.fillCircle(
    image,
    x: card.$1 + (card.$3 * 0.68).round(),
    y: card.$2 + (card.$3 * 0.24).round(),
    radius: (card.$3 * 0.085).round(),
    color: img.ColorRgb8(0xFF, 0xC4, 0x3A),
  );

  return image;
}

/// 返回 (x, y, side)
(int, int, int) _rect(int size,
    {required double left, required double top, required double side}) {
  final s = (size * side).round();
  return ((size * left).round(), (size * top).round(), s);
}
