import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowpic/core/constants.dart';
import 'package:knowpic/services/metadata_store.dart';
import 'package:knowpic/services/pref_transfer.dart';
import 'package:knowpic/services/secure_key_service.dart';

Future<MetadataStore> _storeWithTrainedScene(Directory dir) async {
  final store = MetadataStore(dir);
  await store.init();
  final model = store.scenePreference(AppConfig.scenePortrait);
  final features = List<double>.filled(AppConfig.featureDim, 0.5);
  for (var i = 0; i < 5; i++) {
    model.update(features, 1.0, 1.0);
  }
  return store;
}

void main() {
  test('加密导出 → 导入：权重与样本数往返一致', () async {
    final dir = await Directory.systemTemp.createTemp('knowpic_pref');
    final store = await _storeWithTrainedScene(dir);
    final keys = SecureKeyService(dir);

    final file = await PrefTransfer.exportPreferences(store, keys, dir);
    expect(await file.exists(), isTrue);

    // 分享出去的文件里不能出现明文权重
    final raw = await file.readAsString();
    expect(raw.contains('weights'), isFalse);
    expect(raw.contains(AppConfig.scenePortrait), isFalse);

    final imported = await PrefTransfer.readPreferences(file, keys);
    final scene = imported[AppConfig.scenePortrait];
    expect(scene, isNotNull);
    expect(scene!.sampleCount, store.preferences[AppConfig.scenePortrait]!.sampleCount);
    expect(scene.weights.length, AppConfig.featureDim);
    for (var i = 0; i < AppConfig.featureDim; i++) {
      expect(scene.weights[i],
          closeTo(store.preferences[AppConfig.scenePortrait]!.weights[i], 1e-9));
    }
  });

  test('另一台设备的密钥：解密失败', () async {
    final dir = await Directory.systemTemp.createTemp('knowpic_pref');
    final other = await Directory.systemTemp.createTemp('knowpic_pref_other');
    final store = await _storeWithTrainedScene(dir);
    final file = await PrefTransfer.exportPreferences(store, SecureKeyService(dir), dir);

    expect(
      () => PrefTransfer.readPreferences(file, SecureKeyService(other)),
      throwsA(isA<PrefTransferException>()),
    );
  });

  test('密文被篡改：GCM 校验挡住', () async {
    final dir = await Directory.systemTemp.createTemp('knowpic_pref');
    final store = await _storeWithTrainedScene(dir);
    final keys = SecureKeyService(dir);
    final file = await PrefTransfer.exportPreferences(store, keys, dir);

    final json = await file.readAsString();
    // 翻转密文里的一个字符
    final tampered = json.replaceFirst('"data":"', '"data":"X');
    await file.writeAsString(tampered);

    expect(
      () => PrefTransfer.readPreferences(file, keys),
      throwsA(isA<PrefTransferException>()),
    );
  });

  test('重复导出会清掉旧的导出文件', () async {
    final dir = await Directory.systemTemp.createTemp('knowpic_pref');
    final store = await _storeWithTrainedScene(dir);
    final keys = SecureKeyService(dir);
    await PrefTransfer.exportPreferences(store, keys, dir);
    await PrefTransfer.exportPreferences(store, keys, dir);

    final exports = await dir
        .list(recursive: false)
        .where((e) => e.path.endsWith('.${PrefTransfer.fileExtension}'))
        .length;
    expect(exports, 1);
  });
}
