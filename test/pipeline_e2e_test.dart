import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:knowpic/core/constants.dart';
import 'package:knowpic/models/photo_asset.dart';
import 'package:knowpic/models/trash_item.dart';
import 'package:knowpic/services/learning_service.dart';
import 'package:knowpic/services/metadata_store.dart';
import 'package:knowpic/services/photo_library_service.dart';
import 'package:knowpic/services/ranking_service.dart';
import 'package:knowpic/services/scanner_service.dart';
import 'package:knowpic/services/similarity_service.dart';
import 'package:knowpic/services/trash_service.dart';

/// 内存假相册：用合成图片驱动完整真实管线（特征提取走真 Isolate）
class _FakeLibrary implements PhotoLibraryService {
  final Map<String, PhotoAsset> assets = {};
  final Map<String, Uint8List> bytes = {};
  final List<String> deletedIds = [];
  final List<String> savedFilenames = [];
  int _saveCounter = 0;
  bool granted = true;

  @override
  Future<bool> requestPermission() async => granted;
  @override
  Future<bool> checkPermission() async => granted;
  @override
  bool get hasPermission => granted;

  @override
  Future<List<PhotoAsset>> loadAllPhotos({
    void Function(int done)? onProgress,
    DateTime? newerThan,
  }) async {
    final list = assets.values
        .where((a) => newerThan == null || a.createdTime.isAfter(newerThan))
        .toList();
    onProgress?.call(list.length);
    return list;
  }

  @override
  Future<Uint8List?> loadThumbnail(String id, {int size = 512}) async =>
      bytes[id];

  @override
  Future<Uint8List?> loadOriginalBytes(String id) async => bytes[id];

  @override
  Future<List<String>> deleteAssets(List<String> ids) async {
    deletedIds.addAll(ids);
    return const []; // 全部删除成功
  }

  @override
  Future<String> saveImageToAlbum(
    Uint8List data, {
    required String filename,
    String? title,
  }) async {
    savedFilenames.add(filename);
    return 'restored-${_saveCounter++}';
  }

  @override
  Future<void> openSystemSettings() async {}
}

/// 水平渐变（左黑右白）
Uint8List _horizontalGradient() {
  final im = img.Image(width: 256, height: 256);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      final v = x;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

/// 竖条纹（横向相邻像素交替明暗）—— dHash 非 0 且与水平渐变完全不同
Uint8List _verticalGradient() {
  final im = img.Image(width: 256, height: 256);
  for (var y = 0; y < 256; y++) {
    for (var x = 0; x < 256; x++) {
      final v = (x ~/ 32).isEven ? 30 : 225;
      im.setPixelRgb(x, y, v, v, v);
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

double _l1(Float32List v) {
  var s = 0.0;
  for (final x in v) {
    s += x.abs();
  }
  return s;
}

void main() {
  test('完整扫描管线：合成图→特征提取(真Isolate)→聚类→原子持久化→重载特征配对', () async {
    final dir = await Directory.systemTemp.createTemp('knowpic_pipe');
    final store = MetadataStore(dir);
    await store.init();
    final lib = _FakeLibrary();

    final hBytes = _horizontalGradient();
    final vBytes = _verticalGradient();
    final now = DateTime(2026, 9, 1, 12, 0, 0);
    // 两张相同水平渐变（重复对）+ 两张相同垂直渐变（重复对）
    final defs = [
      ('a', 'a.jpg', hBytes, now),
      ('b', 'b.jpg', hBytes, now.add(const Duration(seconds: 1))),
      ('c', 'c.jpg', vBytes, now),
      ('d', 'd.jpg', vBytes, now.add(const Duration(seconds: 1))),
    ];
    for (final (id, title, data, t) in defs) {
      lib.bytes[id] = data;
      lib.assets[id] = PhotoAsset(
        id: id,
        title: title,
        width: 256,
        height: 256,
        byteSize: data.length,
        createdTime: t,
      );
    }

    final scanner = ScannerService(
      library: lib,
      store: store,
      similarity: SimilarityService(),
      ranking: RankingService(LearningService(store)),
    );
    final result = await scanner.fullScan();

    // 聚类：两对完全重复 → 2 组
    expect(result.groups, 2, reason: '两个重复对应聚为 2 组');
    expect(result.totalPhotos, 4);
    expect(store.assets.length, 4);

    // 持久化文件存在，原子写不留 .tmp 残留
    final metaDir = Directory('${dir.path}/${AppConfig.rootDirName}');
    final files = await metaDir.list().map((f) => f.uri.pathSegments.last).toList();
    expect(files, contains(AppConfig.assetsFile));
    expect(files, contains(AppConfig.featuresFile));
    expect(files.where((n) => n.endsWith('.tmp')), isEmpty,
        reason: '原子写不应留下 .tmp 文件');

    // 特征已分析（L1 归一化为 2.0）
    for (final a in store.assets.values) {
      expect(_l1(a.features), closeTo(2.0, 0.05),
          reason: '${a.id} 特征应已提取并 L1 归一化');
      expect(a.dHash, isNot(0), reason: '${a.id} 应有 dHash');
    }

    // 全新 store 重载：assets.json + features.bin 配对正确
    final store2 = MetadataStore(dir);
    await store2.init();
    expect(store2.assets.length, 4);
    expect(store2.groups.length, 2);
    for (final a in store2.assets.values) {
      expect(_l1(a.features), closeTo(2.0, 0.05),
          reason: '重载后 ${a.id} 特征配对应正确');
    }
  });

  test('特征文件截断/行数不匹配：不崩溃，降级为待重扫（不错误配对）', () async {
    final dir = await Directory.systemTemp.createTemp('knowpic_corrupt');
    final store = MetadataStore(dir);
    await store.init();
    final lib = _FakeLibrary();
    final hBytes = _horizontalGradient();
    for (final id in ['a', 'b']) {
      lib.bytes[id] = hBytes;
      lib.assets[id] = PhotoAsset(
        id: id,
        title: '$id.jpg',
        width: 256,
        height: 256,
        byteSize: hBytes.length,
        createdTime: DateTime(2026, 9, 1),
      );
    }
    final scanner = ScannerService(
      library: lib,
      store: store,
      similarity: SimilarityService(),
      ranking: RankingService(LearningService(store)),
    );
    await scanner.fullScan();

    // 破坏 features.bin：截断掉半行以上（行数变成 1 ≠ 资产数 2）
    final featFile =
        File('${dir.path}/${AppConfig.rootDirName}/${AppConfig.featuresFile}');
    final good = await featFile.readAsBytes();
    await featFile.writeAsBytes(good.sublist(0, AppConfig.featureDim * 4 + 10));

    final store2 = MetadataStore(dir);
    await store2.init(); // 不应抛异常
    expect(store2.assets.length, 2);
    for (final a in store2.assets.values) {
      expect(_l1(a.features), 0.0, reason: '配对守卫应放弃损坏的特征文件');
    }
  });

  test('回收站全链路：软删除备份→还原真实扩展名→路径穿越消毒', () async {
    final dir = await Directory.systemTemp.createTemp('knowpic_trash');
    final store = MetadataStore(dir);
    await store.init();
    final lib = _FakeLibrary();
    final hBytes = _horizontalGradient();
    lib.bytes['p'] = hBytes;
    store.assets['p'] = PhotoAsset(
      id: 'p',
      title: 'photo.png',
      width: 256,
      height: 256,
      byteSize: hBytes.length,
      createdTime: DateTime(2026, 9, 1),
    );

    final trash = TrashService(store, lib);

    // 软删除：备份文件写入消毒后的路径
    final r = await trash.softDelete(['p'], store.assets);
    expect(r.trashedCount, 1);
    expect(lib.deletedIds, contains('p'));
    expect(store.trashItems.length, 1);
    final item = store.trashItems.single;
    expect(item.savedFileName.contains(RegExp(r'[/\\]|\.\.')), isFalse,
        reason: '备份文件名必须经消毒');
    final backup = store.trashFileOf(item);
    expect(await backup.exists(), isTrue);
    expect(backup.parent.path, store.trashDir.path,
        reason: '备份文件必须在回收站目录内');

    // 还原：文件名保留备份扩展名（此处 .jpg，因为标题 photo.png 但备份用 _safeExt 从 title 得 png...）
    final restored = await trash.restore(['p']);
    expect(restored, ['p']);
    expect(lib.savedFilenames.single, isNot(endsWith('.jpg')),
        reason: '原图标题为 .png，还原扩展名应为 .png');
    expect(lib.savedFilenames.single, endsWith('.png'));
    expect(await backup.exists(), isFalse, reason: '还原后备份应删除');
    expect(store.trashItems, isEmpty);

    // 路径穿越：manifest 被篡改为 ../../ 逃逸路径时，trashFileOf 仍锁在回收站目录
    final evil = TrashItem(
      id: 'x',
      originalTitle: 'x.jpg',
      savedFileName: '../../../../tmp/evil.bin',
      byteSize: 1,
      deletedAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
    final safePath = store.trashFileOf(evil);
    expect(safePath.parent.path, store.trashDir.path);
    expect(safePath.path.contains('..'), isFalse);
  });

  test('loadAllPhotos 时间下界早停契约：仅返回 newerThan 之后的资产', () async {
    final lib = _FakeLibrary();
    final old = PhotoAsset(
      id: 'old',
      title: 'old.jpg',
      width: 10,
      height: 10,
      byteSize: 1,
      createdTime: DateTime.now().subtract(const Duration(days: 100)),
    );
    final recent = PhotoAsset(
      id: 'new',
      title: 'new.jpg',
      width: 10,
      height: 10,
      byteSize: 1,
      createdTime: DateTime.now().subtract(const Duration(days: 2)),
    );
    lib.assets['old'] = old;
    lib.assets['new'] = recent;

    final all = await lib.loadAllPhotos();
    expect(all.length, 2);

    final recentOnly = await lib.loadAllPhotos(
      newerThan: DateTime.now().subtract(const Duration(days: 30)),
    );
    expect(recentOnly.map((a) => a.id), ['new']);
  });
}
