import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/logger.dart';
import 'providers/providers.dart';
import 'services/app_settings.dart';
import 'services/app_storage.dart';
import 'services/metadata_store.dart';

/// 启动入口。保持返回 `Future<void>`：integration_test / test_driver 会 await 它。
/// 外层再套一层 Zone 兜底：release 下 framework 外的异步错误默认被静默吞掉。
Future<void> main() =>
    runZonedGuarded(_bootstrap, _onZoneError) ?? Future<void>.value();

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installErrorHandlers();

  // 初始化本地数据层（文档 6.1 目录结构）
  // 根目录走 AppStorage：数据不落在会进 iCloud 备份的 Documents
  final root = await AppStorage.resolveRoot();
  final store = MetadataStore(root);
  await store.init();
  // 启动即对账：清掉 manifest 里没有记录的孤儿备份文件
  // （上次清理时备份写盘成功但 manifest 没写就崩溃 → 已删照片一直明文占着磁盘）
  await store.cleanOrphanTrashFiles();
  final settings = await AppSettings.load(root);

  runApp(
    ProviderScope(
      overrides: [
        storeProvider.overrideWithValue(store),
        settingsProvider.overrideWith(
          () => SettingsController()..initial = settings,
        ),
      ],
      child: const KnowPicApp(),
    ),
  );
}

void _onZoneError(Object error, StackTrace stack) =>
    Log.e('Zone', '$error', stack);

void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Log.e('Flutter', '${details.exception}', details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    Log.e('Platform', '$error', stack);
    return true;
  };
}
