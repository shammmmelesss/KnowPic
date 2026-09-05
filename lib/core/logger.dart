import 'package:flutter/foundation.dart';

/// 轻量日志工具（debug 模式打印，release 静默）
class Log {
  Log._();

  static bool _enabled = kDebugMode;

  static void setEnabled(bool value) => _enabled = value;

  static void d(String tag, String message) {
    if (_enabled) {
      // ignore: avoid_print
      print('[$tag] $message');
    }
  }

  static void e(String tag, String message, [Object? error]) {
    if (_enabled) {
      // ignore: avoid_print
      print('[$tag][ERROR] $message ${error ?? ""}');
    }
  }
}
