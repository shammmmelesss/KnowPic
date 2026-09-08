import 'package:flutter/services.dart';

/// 触感反馈（HIG「Playing Haptics」：按语义使用系统反馈模式）
class Haptics {
  Haptics._();

  /// 普通轻点
  static void tap() => HapticFeedback.lightImpact();

  /// 选择/切换（分段控件、标记保留）
  static void selection() => HapticFeedback.selectionClick();

  /// 操作成功
  static void success() => HapticFeedback.mediumImpact();

  /// 警示/失败
  static void warning() => HapticFeedback.heavyImpact();
}
