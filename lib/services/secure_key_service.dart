import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';

import '../core/logger.dart';

/// 偏好导出/导入用的对称密钥。
///
/// 首选 iOS 钥匙串（原生侧 knowpic/secure 通道，见 ios/Runner/AppDelegate.swift）：
/// 密钥存在 Keychain 且标记 WhenUnlockedThisDeviceOnly —— 不进 iCloud 备份、
/// 不随设备迁移，重装 App 后旧备份文件自然失效。
/// 原生通道不可用时（非 iOS / 通道未注册）回退到应用私有目录下的密钥文件，
/// 保证功能在测试与桌面端仍可用。
class SecureKeyService {
  SecureKeyService(this._dir);

  static const MethodChannel _channel = MethodChannel('knowpic/secure');
  static const int keyBytes = 32; // AES-256
  static const String _fallbackFileName = '.knowpic_export_key';

  final Directory _dir;
  Uint8List? _cached;

  /// 取回（必要时生成）32 字节密钥
  Future<Uint8List> key() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final b64 = await _channel.invokeMethod<String>('getOrCreateKey');
      if (b64 != null && b64.isNotEmpty) {
        final bytes = base64Decode(b64);
        if (bytes.length == keyBytes) return _cached = bytes;
        Log.e('SecureKey', 'keychain returned ${bytes.length} bytes, ignore');
      }
    } on MissingPluginException {
      // 原生侧未注册：走文件回退
    } on PlatformException catch (err) {
      Log.e('SecureKey', 'keychain unavailable: ${err.code}', err);
    } catch (err) {
      Log.e('SecureKey', 'keychain failed', err);
    }
    return _cached ??= await _fallbackKey();
  }

  /// 重置密钥（偏好重置时同步作废旧的导出文件）
  Future<void> reset() async {
    _cached = null;
    try {
      await _channel.invokeMethod<bool>('deleteKey');
    } on MissingPluginException {
      // ignore
    } catch (err) {
      Log.e('SecureKey', 'delete key failed', err);
    }
    final f = _fallbackFile();
    try {
      if (await f.exists()) await f.delete();
    } catch (err) {
      Log.e('SecureKey', 'delete fallback key failed', err);
    }
  }

  File _fallbackFile() => File('${_dir.path}${Platform.pathSeparator}$_fallbackFileName');

  Future<Uint8List> _fallbackKey() async {
    final f = _fallbackFile();
    try {
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        if (bytes.length == keyBytes) return Uint8List.fromList(bytes);
      }
      final fresh = _randomBytes();
      await f.writeAsBytes(fresh, flush: true);
      return fresh;
    } catch (err) {
      Log.e('SecureKey', 'fallback key failed', err);
      // 内存态兜底：仅本次会话可用，至少不会让导出/导入直接失败
      return _randomBytes();
    }
  }

  static Uint8List _randomBytes() {
    final rnd = math.Random.secure();
    final out = Uint8List(keyBytes);
    for (var i = 0; i < keyBytes; i++) {
      out[i] = rnd.nextInt(256);
    }
    return out;
  }
}
