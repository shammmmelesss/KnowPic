import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'providers/providers.dart';
import 'services/app_settings.dart';
import 'services/metadata_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地数据层（文档 6.1 目录结构）
  final docs = await getApplicationDocumentsDirectory();
  final store = MetadataStore(docs);
  await store.init();
  final settings = await AppSettings.load(docs);

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
