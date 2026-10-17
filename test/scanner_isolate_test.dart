import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowpic/models/photo_asset.dart';
import 'package:knowpic/models/similar_group.dart';
import 'package:knowpic/services/similarity_service.dart';

/// 隔离区内执行的聚类：与 scanner_service 的 _clusterAssets 同构，
/// 闭包只捕获可跨隔离区发送的纯数据。
List<SimilarGroup> _clusterAssets(List<PhotoAsset> assets) =>
    SimilarityService().clusterAndClassify(assets);

/// 反面教材：实例方法内「引用字段」的闭包会连带捕获 this。
/// 生产环境等价于 ScannerService.progress → 监听器 → Riverpod 控制器 → _Future，
/// 序列化必然失败、退回主隔离区执行，O(n²) 聚类会卡住 UI。
class _LegacyHost {
  _LegacyHost() {
    progress.addListener(() {
      // 监听器闭包捕获 this，把 _pending（Future）带进对象图
      _seen = _pending.hashCode;
    });
  }

  final ValueNotifier<int> progress = ValueNotifier(0);
  final Future<void> _pending = Future<void>.value();
  final   SimilarityService _svc = SimilarityService();
  int _seen = 0;

  int get seen => _seen;

  Future<List<SimilarGroup>> legacy(List<PhotoAsset> assets) =>
      Isolate.run(() => _svc.clusterAndClassify(assets));
}

List<PhotoAsset> _assets() => [
      PhotoAsset(
        id: 'a',
        title: 'a.jpg',
        width: 100,
        height: 100,
        byteSize: 1000,
        createdTime: DateTime(2026, 1, 1),
        dHash: 0x0F,
      ),
      PhotoAsset(
        id: 'b',
        title: 'b.jpg',
        width: 100,
        height: 100,
        byteSize: 1000,
        createdTime: DateTime(2026, 1, 1),
        dHash: 0x0A, // 与 a 汉明距离 2 → 同组
      ),
    ];

void main() {
  test('顶层闭包：聚类可在隔离区执行', () async {
    final groups = await Isolate.run(() => _clusterAssets(_assets()));
    expect(groups.length, 1);
    expect(groups.first.assetIds.toSet(), {'a', 'b'});
  });

  test('实例字段闭包会被隔离区拒绝（修复前的失败链路）', () async {
    final host = _LegacyHost();
    host.progress.value = 1; // 触发一次监听器，确认它确实挂在 progress 上
    await expectLater(host.legacy(_assets()), throwsArgumentError);
    expect(host.seen, isNot(0));
  });
}
