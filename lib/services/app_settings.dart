import 'dart:convert';
import 'dart:io';

import '../core/constants.dart';
import '../core/logger.dart';

/// 应用设置（隐私优先：埋点默认关闭，仅用户同意后开启）
class AppSettings {
  AppSettings({
    this.helpImprove = false,
    this.confirmBeforeDelete = true,
    this.lastScanAt,
  });

  /// 帮助改进（脱敏埋点，默认关）
  bool helpImprove;

  /// 清理前二次确认（默认开）
  bool confirmBeforeDelete;

  DateTime? lastScanAt;

  AppSettings copyWith({
    bool? helpImprove,
    bool? confirmBeforeDelete,
    DateTime? lastScanAt,
  }) {
    return AppSettings(
      helpImprove: helpImprove ?? this.helpImprove,
      confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
      lastScanAt: lastScanAt ?? this.lastScanAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'helpImprove': helpImprove,
        'confirmBeforeDelete': confirmBeforeDelete,
        'lastScanAt': lastScanAt?.toIso8601String(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      helpImprove: json['helpImprove'] as bool? ?? false,
      confirmBeforeDelete: json['confirmBeforeDelete'] as bool? ?? true,
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
    final f = File('${rootDir.path}/${AppConfig.rootDirName}/${AppConfig.settingsFile}');
    await f.writeAsString(jsonEncode(toJson()), flush: true);
  }
}
