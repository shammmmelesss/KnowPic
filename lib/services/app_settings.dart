import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';
import '../core/logger.dart';

/// 应用设置（隐私优先：埋点默认关闭，仅用户同意后开启）
class AppSettings {
  AppSettings({
    this.helpImprove = false,
    this.confirmBeforeDelete = true,
    this.languageMode = 'system',
    this.lastScanAt,
  });

  /// 帮助改进（脱敏埋点，默认关）
  bool helpImprove;

  /// 清理前二次确认（默认开）
  bool confirmBeforeDelete;

  /// 显示语言：'system' | 'zh' | 'en'（默认跟随系统）
  String languageMode;

  DateTime? lastScanAt;

  AppSettings copyWith({
    bool? helpImprove,
    bool? confirmBeforeDelete,
    String? languageMode,
    DateTime? lastScanAt,
  }) {
    return AppSettings(
      helpImprove: helpImprove ?? this.helpImprove,
      confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
      languageMode: languageMode ?? this.languageMode,
      lastScanAt: lastScanAt ?? this.lastScanAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'helpImprove': helpImprove,
        'confirmBeforeDelete': confirmBeforeDelete,
        'languageMode': languageMode,
        'lastScanAt': lastScanAt?.toIso8601String(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      helpImprove: json['helpImprove'] as bool? ?? false,
      confirmBeforeDelete: json['confirmBeforeDelete'] as bool? ?? true,
      languageMode: json['languageMode'] as String? ?? 'system',
      lastScanAt: DateTime.tryParse(json['lastScanAt'] as String? ?? ''),
    );
  }

  static Future<AppSettings> load(Directory rootDir) async {
    final f = File('${rootDir.path}/${AppConfig.rootDirName}/${AppConfig.settingsFile}');
    if (!await f.exists()) return AppSettings();
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return AppSettings.fromJson(json);
    } catch (err) {
      Log.e('Settings', 'load failed', err);
      return AppSettings();
    }
  }

  Future<void> save(Directory rootDir) async {
    // 原子写（.tmp → rename），避免写一半崩溃损坏设置文件
    final f = File('${rootDir.path}/${AppConfig.rootDirName}/${AppConfig.settingsFile}');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    await tmp.rename(f.path);
  }
}
