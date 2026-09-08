import 'package:flutter/material.dart';

/// iOS 设计令牌（基于 Apple Human Interface Guidelines）
/// 颜色取自 iOS 系统色板，排版对齐 SF Pro 层级（中文自动回退苹方）。
/// 参考：https://developer.apple.com/design/human-interface-guidelines/
class Ios {
  Ios._();

  // ---- 系统色（light / dark 双态精确值） ----
  static const _blueL = Color(0xFF007AFF);
  static const _blueD = Color(0xFF0A84FF);
  static const _greenL = Color(0xFF34C759);
  static const _greenD = Color(0xFF30D158);
  static const _redL = Color(0xFFFF3B30);
  static const _redD = Color(0xFFFF453A);
  static const _orangeL = Color(0xFFFF9500);
  static const _orangeD = Color(0xFFFF9F0A);
  static const _purpleL = Color(0xFFAF52DE);
  static const _purpleD = Color(0xFFBF5AF2);
  static const _indigoL = Color(0xFF5856D6);
  static const _indigoD = Color(0xFF5E5CE6);

  static Color blue(Brightness b) => b == Brightness.dark ? _blueD : _blueL;
  static Color green(Brightness b) => b == Brightness.dark ? _greenD : _greenL;
  static Color red(Brightness b) => b == Brightness.dark ? _redD : _redL;
  static Color orange(Brightness b) =>
      b == Brightness.dark ? _orangeD : _orangeL;
  static Color purple(Brightness b) =>
      b == Brightness.dark ? _purpleD : _purpleL;
  static Color indigo(Brightness b) =>
      b == Brightness.dark ? _indigoD : _indigoL;

  // ---- 语义背景与文字（grouped background 体系） ----
  static Color bg(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  static Color card(Brightness b) =>
      b == Brightness.dark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
  static Color label(Brightness b) =>
      b == Brightness.dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  static Color secondaryLabel(Brightness b) =>
      b == Brightness.dark ? const Color(0x99EBEBF5) : const Color(0x993C3C67);
  static Color tertiaryLabel(Brightness b) =>
      b == Brightness.dark ? const Color(0x4DEBEBF5) : const Color(0x4D3C3C67);
  static Color separator(Brightness b) =>
      b == Brightness.dark ? const Color(0x99545458) : const Color(0x4A3C3C67);
  static Color fill(Brightness b) =>
      b == Brightness.dark ? const Color(0x5C787880) : const Color(0x1F767680);

  // ---- 圆角 ----
  static const double radiusCard = 12;
  static const double radiusThumb = 8;
  static const double radiusMedia = 16;

  // ---- 排版（SF Pro 层级，中文回退苹方） ----
  static TextTheme textTheme(Brightness b) {
    final label = Ios.label(b);
    final secondary = Ios.secondaryLabel(b);
    return TextTheme(
      displayLarge: TextStyle(
          fontSize: 34,
          height: 1.21,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.37,
          color: label),
      displayMedium: TextStyle(
          fontSize: 28,
          height: 1.14,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.36,
          color: label),
      displaySmall: TextStyle(
          fontSize: 22,
          height: 1.18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.35,
          color: label),
      headlineLarge: TextStyle(
          fontSize: 22,
          height: 1.18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.35,
          color: label),
      headlineMedium: TextStyle(
          fontSize: 20,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: label),
      headlineSmall: TextStyle(
          fontSize: 17,
          height: 1.29,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.41,
          color: label),
      titleLarge: TextStyle(
          fontSize: 34,
          height: 1.21,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.37,
          color: label),
      titleMedium: TextStyle(
          fontSize: 17,
          height: 1.29,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.41,
          color: label),
      titleSmall: TextStyle(
          fontSize: 15,
          height: 1.33,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.24,
          color: label),
      bodyLarge: TextStyle(
          fontSize: 17,
          height: 1.29,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.41,
          color: label),
      bodyMedium: TextStyle(
          fontSize: 15,
          height: 1.33,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.24,
          color: label),
      bodySmall: TextStyle(
          fontSize: 13,
          height: 1.38,
          fontWeight: FontWeight.w400,
          letterSpacing: -0.08,
          color: secondary),
      labelLarge: TextStyle(
          fontSize: 17,
          height: 1.29,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.41,
          color: label),
      labelMedium: TextStyle(
          fontSize: 12,
          height: 1.33,
          fontWeight: FontWeight.w500,
          color: secondary),
      labelSmall: TextStyle(
          fontSize: 11,
          height: 1.18,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.06,
          color: secondary),
    );
  }

  /// 字节数人性化（统一各页面文案）
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
