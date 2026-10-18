import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../core/logger.dart';
import '../models/preference_model.dart';
import 'metadata_store.dart';
import 'secure_key_service.dart';

/// 偏好文件损坏 / 版本不符 / 密钥不对（解密失败）
class PrefTransferException implements Exception {
  PrefTransferException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 偏好的加密导出与导入。
///
/// 导出文件是自描述的信封（版本 + 算法 + nonce + MAC + 密文），
/// 明文的偏好模型绝不落盘到分享出去的文件里。
class PrefTransfer {
  PrefTransfer._();

  static const int version = 1;
  static const String algorithm = 'AES-GCM-256';
  static const String fileExtension = 'kpic';
  static const String _filePrefix = 'knowpic-preference-';

  static final AesGcm _aes = AesGcm.with256bits();

  /// 加密导出偏好，返回生成的文件（已写入磁盘，可直接交给分享）。
  /// [dir] 建议传应用私有目录；同目录下旧的导出文件会先被清掉。
  static Future<File> exportPreferences(
    MetadataStore store,
    SecureKeyService keys,
    Directory dir,
  ) async {
    await _clearOldExports(dir);
    final payload = jsonEncode(<String, dynamic>{
      'scenes': store.preferences.map((k, v) => MapEntry(k, v.toJson())),
    });
    final box = await _aes.encrypt(
      utf8.encode(payload),
      secretKey: SecretKey(await keys.key()),
    );
    final file = File(
      '${dir.path}${Platform.pathSeparator}$_filePrefix${_stamp()}.$fileExtension',
    );
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'v': version,
        'alg': algorithm,
        'nonce': base64Encode(box.nonce),
        'mac': base64Encode(box.mac.bytes),
        'data': base64Encode(box.cipherText),
      }),
      flush: true,
    );
    return file;
  }

  /// 解密读取导出文件，返回 sceneKey -> PreferenceModel。
  /// 任何格式/完整性/密钥问题都抛 [PrefTransferException]（GCM 的 MAC 校验会挡住篡改）。
  static Future<Map<String, PreferenceModel>> readPreferences(
    File file,
    SecureKeyService keys,
  ) async {
    Map<String, dynamic> envelope;
    try {
      envelope = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (err) {
      throw PrefTransferException('无法解析文件：$err');
    }
    final v = envelope['v'] as int?;
    if (v != version) throw PrefTransferException('不支持的文件版本：$v');
    if (envelope['alg'] != algorithm) {
      throw PrefTransferException('不支持的算法：${envelope['alg']}');
    }

    SecretBox box;
    try {
      box = SecretBox(
        base64Decode(envelope['data'] as String),
        nonce: base64Decode(envelope['nonce'] as String),
        mac: Mac(base64Decode(envelope['mac'] as String)),
      );
    } catch (_) {
      throw PrefTransferException('文件内容已损坏');
    }
    List<int> clear;
    try {
      clear = await _aes.decrypt(box, secretKey: SecretKey(await keys.key()));
    } catch (err) {
      // 解密失败 = 密钥不对或文件被改过，不要把细节抛给用户
      throw PrefTransferException('解密失败：文件已损坏或不属于本设备');
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    } catch (err) {
      throw PrefTransferException('偏好内容已损坏');
    }
    final scenes = decoded['scenes'];
    if (scenes is! Map<String, dynamic> || scenes.isEmpty) {
      throw PrefTransferException('文件里没有偏好数据');
    }
    final out = <String, PreferenceModel>{};
    var skipped = 0;
    scenes.forEach((key, value) {
      try {
        out[key] = PreferenceModel.fromJson(value as Map<String, dynamic>);
      } catch (err) {
        skipped++;
        Log.e('PrefTransfer', 'bad scene record skipped', err);
      }
    });
    if (out.isEmpty) throw PrefTransferException('偏好数据全部无法解析');
    if (skipped > 0) Log.e('PrefTransfer', '$skipped scene(s) skipped');
    return out;
  }

  /// 统计导入文件里的样本总数（用于导入确认弹窗）
  static int totalSamples(Map<String, PreferenceModel> models) =>
      models.values.fold<int>(0, (s, m) => s + m.sampleCount);

  static Future<void> _clearOldExports(Directory dir) async {
    try {
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: false)) {
        if (entity is! File) continue;
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith(_filePrefix) && name.endsWith('.$fileExtension')) {
          await entity.delete();
        }
      }
    } catch (err) {
      Log.e('PrefTransfer', 'clear old exports failed', err);
    }
  }

  static String _stamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }
}
