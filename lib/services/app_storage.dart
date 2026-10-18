import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';
import '../core/logger.dart';

/// 应用数据根目录解析（隐私优先）。
///
/// 背景：iOS 的 Documents 目录默认随 iCloud/iTunes 备份上传，且本应用会在
/// `trash/` 下明文留存用户「已删除」的原图。放在 Documents 等于把最敏感的
/// 数据悄悄同步到云端。这里统一改用 `Application Support`：
/// - 不暴露给「文件」App（用户无法直接翻看）；
/// - iOS 原生侧对该目录显式设置 `NSURLIsExcludedFromBackupKey`
///   （见 ios/Runner/AppDelegate.swift），不进备份。
class AppStorage {
  AppStorage._();

  /// 解析数据根目录，并把旧版本留在 Documents 的数据迁移过来。
  static Future<Directory> resolveRoot() async {
    final support = await getApplicationSupportDirectory();
    await _migrateLegacyData(support);
    return support;
  }

  /// 旧版本数据存放在 Documents/knowpic，迁移到 Application Support/knowpic。
  /// 迁移失败不影响启动：最坏情况是用户重新扫描一次。
  static Future<void> _migrateLegacyData(Directory newRoot) async {
    Directory oldDir;
    try {
      final docs = await getApplicationDocumentsDirectory();
      oldDir = Directory('${docs.path}/${AppConfig.rootDirName}');
    } catch (err) {
      Log.e('Storage', 'legacy dir unavailable', err);
      return;
    }
    final newDir = Directory('${newRoot.path}/${AppConfig.rootDirName}');
    try {
      if (await newDir.exists()) return;
      if (!await oldDir.exists()) return;
      // 同一沙盒内 rename 是原子操作；跨卷失败时回退为复制
      await oldDir.rename(newDir.path);
      Log.d('Storage', 'migrated legacy data to ${_leaf(newDir.path)}');
    } catch (err) {
      Log.e('Storage', 'rename failed, fallback to copy', err);
      await _copyDirectory(oldDir, newDir);
    }
  }

  static Future<void> _copyDirectory(Directory from, Directory to) async {
    try {
      if (!await to.exists()) await to.create(recursive: true);
      await for (final entity in from.list(recursive: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        final target = '${to.path}${Platform.pathSeparator}$name';
        if (entity is Directory) {
          await _copyDirectory(entity, Directory(target));
        } else if (entity is File) {
          await entity.copy(target);
        }
      }
    } catch (err) {
      Log.e('Storage', 'copy legacy data failed', err);
    }
  }

  /// 日志脱敏：只保留路径最后一段，避免把完整沙盒路径（含 App UUID）打进日志
  static String _leaf(String path) {
    final parts = path.split(Platform.pathSeparator);
    return parts.isEmpty ? path : parts.last;
  }
}
