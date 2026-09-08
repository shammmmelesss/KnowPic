import 'package:flutter_driver/driver_extension.dart';

import 'package:knowpic/main.dart' as app;

/// flutter_driver 目标入口：启用驱动扩展后启动真实应用
Future<void> main() async {
  enableFlutterDriverExtension();
  await app.main();
}
