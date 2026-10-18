import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:knowpic/core/constants.dart';
import 'package:knowpic/l10n/app_strings.dart';
import 'package:knowpic/models/best_reason.dart';
import 'package:knowpic/models/group_type.dart';
import 'package:knowpic/models/photo_asset.dart';
import 'package:knowpic/models/preference_model.dart';
import 'package:knowpic/models/user_action.dart';
import 'package:knowpic/services/learning_service.dart';
import 'package:knowpic/services/memory_service.dart';
import 'package:knowpic/services/metadata_store.dart';
import 'package:knowpic/services/ranking_service.dart';
import 'package:knowpic/services/similarity_service.dart';

PhotoAsset _asset(
  String id, {
  int dHash = 0,
  int width = 100,
  int height = 100,
  int byteSize = 1000,
  String title = 'photo.jpg',
  DateTime? created,
  Float32List? features,
  double baseScore = 5,
  String sceneType = AppConfig.sceneOther,
}) {
  return PhotoAsset(
    id: id,
    title: title,
    width: width,
    height: height,
    byteSize: byteSize,
    createdTime: created ?? DateTime(2026, 1, 1),
    dHash: dHash,
    features: features,
    baseScore: baseScore,
    sceneType: sceneType,
  );
}

void main() {
  group('SimilarityService 聚类', () {
    test('相同 dHash 的照片聚为 1 个重复组', () {
      final svc = SimilarityService();
      final groups = svc.clusterAndClassify([
        _asset('a', dHash: 0x0F),
        _asset('b', dHash: 0x0A), // 汉明距离 2 ≤ 4 → 重复
      ]);
      expect(groups, hasLength(1));
      expect(groups.first.type, GroupType.duplicate);
      expect(groups.first.size, 2);
    });

    test('截图标题 + 相同哈希 → 截图组', () {
      final svc = SimilarityService();
      final now = DateTime(2026, 3, 1, 12, 0, 0);
      final groups = svc.clusterAndClassify([
        _asset('a', dHash: 0x00, title: 'IMG_Screenshot_001', created: now),
        _asset('b', dHash: 0x00, title: 'IMG_Screenshot_002', created: now),
      ]);
      expect(groups, hasLength(1));
      expect(groups.first.type, GroupType.screenshot);
    });

    test('连拍：3 秒时间窗内、哈希接近 → 连拍组', () {
      final svc = SimilarityService();
      final t = DateTime(2026, 3, 1, 12, 0, 0);
      final groups = svc.clusterAndClassify([
        _asset('a', dHash: 0x00, byteSize: 1000, created: t),
        _asset('b', dHash: 0x07, byteSize: 2000, created: t.add(const Duration(seconds: 1))),
      ]);
      expect(groups, hasLength(1));
      expect(groups.first.type, GroupType.burst);
    });

    test('长图宽高比 → 长图/全景组', () {
      final svc = SimilarityService();
      final groups = svc.clusterAndClassify([
        _asset('a', dHash: 0x0F, width: 200, height: 2000),
        _asset('b', dHash: 0x0A, width: 200, height: 1990),
      ]);
      expect(groups, hasLength(1));
      expect(groups.first.type, GroupType.longShot);
    });

    test('差异大的照片不聚组', () {
      final svc = SimilarityService();
      final groups = svc.clusterAndClassify([
        _asset('a', dHash: 0x0000000000000000),
        _asset('b', dHash: 0xFFFFFFFFFFFFFFFF), // 距离 64
      ]);
      expect(groups, isEmpty);
    });

    test('estimateReclaimable 只计算保留最佳外的空间', () {
      final svc = SimilarityService();
      final groups = svc.clusterAndClassify([
        _asset('a', dHash: 0x0F, byteSize: 1000),
        _asset('b', dHash: 0x0A, byteSize: 3000),
      ]);
      final group = groups.first;
      final byId = {'a': _asset('a', dHash: 0x0F, byteSize: 1000), 'b': _asset('b', dHash: 0x0A, byteSize: 3000)};
      group.bestId = 'b';
      expect(svc.estimateReclaimable(group, byId), 1000);
    });
  });

  group('RankingService 冷启动排序', () {
    test('未训练时按 NIMA 分排序，FinalScore=0.4*NIMA+0.6', () async {
      final dir = await Directory.systemTemp.createTemp('knowpic_test');
      final store = MetadataStore(dir);
      await store.init();
      final ranking = RankingService(LearningService(store));
      final members = [
        _asset('low', baseScore: 3, dHash: 1),
        _asset('high', baseScore: 9, dHash: 2),
      ];
      // sortGroup 返回新列表，不修改入参（避免 build 期间 mutate 共享状态）
      final sorted = ranking.sortGroup(members);
      expect(sorted.first.id, 'high');
      expect(sorted.first.finalScore, closeTo(0.4 * 9 + 0.6 * 1.0, 1e-6));
      expect(ranking.pickBest(members), 'high');
    });

    test('bestReason 返回非空理由', () async {
      final dir = await Directory.systemTemp.createTemp('knowpic_test');
      final store = MetadataStore(dir);
      await store.init();
      final ranking = RankingService(LearningService(store));
      final members = [_asset('a', dHash: 1), _asset('b', dHash: 2)];
      // 服务层只返回枚举，文案由 l10n 解析
      final reason = ranking.bestReason(members.first, members);
      expect(reason, isIn(BestReason.values));
      for (final code in AppStrings.supportedLanguageCodes) {
        expect(AppStrings.ofCode(code).bestReason(reason), isNotEmpty);
      }
    });
  });

  group('PreferenceModel FTRL', () {
    test('update 后权重发生变化且 isTrained=true', () {
      final model = PreferenceModel(dim: 4);
      expect(model.isTrained, isFalse);
      final features = [1.0, 0.0, 0.5, -0.5];
      model.update(features, 1.0, 1.0);
      expect(model.isTrained, isTrue);
      expect(model.sampleCount, 1);
      // 至少一个权重被更新过（非全 0.5）
      expect(model.weights.any((w) => w != 0.5), isTrue);
    });

    test('reset 恢复冷启动状态', () {
      final model = PreferenceModel(dim: 4);
      model.update([1.0, 0.0, 0.5, -0.5], 1.0, 1.0);
      model.reset();
      expect(model.sampleCount, 0);
      expect(model.resetCount, 1);
      expect(model.weights.every((w) => w == 0.5), isTrue);
    });

    test('updatePair 成对学习改变排序', () {
      final model = PreferenceModel(dim: 4);
      final pos = [1.0, 0.0, 0.0, 0.0];
      final neg = [0.0, 1.0, 0.0, 0.0];
      model.updatePair(pos, neg, 1.0);
      final posScore = model.bias +
          model.weights.asMap().entries.fold(0.0, (s, e) => s + e.value * pos[e.key]);
      final negScore = model.bias +
          model.weights.asMap().entries.fold(0.0, (s, e) => s + e.value * neg[e.key]);
      expect(posScore, greaterThan(negScore));
    });
  });

  group('多场景偏好', () {
    test('flush 按正样本场景路由到独立模型，互不干扰', () async {
      final dir = await Directory.systemTemp.createTemp('knowpic_test');
      final store = MetadataStore(dir);
      await store.init();
      final posF = Float32List(AppConfig.featureDim);
      posF[0] = 1.0;
      final negF = Float32List(AppConfig.featureDim);
      store.assets['p'] = _asset('p', sceneType: AppConfig.scenePortrait, features: posF);
      store.assets['l'] = _asset('l', sceneType: AppConfig.sceneLandscape, features: posF);
      store.assets['n'] = _asset('n', features: negF);

      final learning = LearningService(store);
      learning.collect(UserAction(
        assetId: 'p', groupId: 'g', type: ActionType.favorite, timestamp: DateTime.now()));
      learning.collect(UserAction(
        assetId: 'n', groupId: 'g', type: ActionType.delete, timestamp: DateTime.now()));
      await learning.flush();

      final portrait = store.preferences[AppConfig.scenePortrait];
      expect(portrait, isNotNull);
      expect(portrait!.isTrained, isTrue, reason: '人像场景应收到训练样本');
      expect(store.preferences[AppConfig.sceneLandscape], isNull,
          reason: '风景场景没有样本，不应被创建');
      // 全局汇总模型同步学习，供 UI 展示与兜底
      expect(learning.model.isTrained, isTrue);
      expect(learning.models.length, 2); // all + portrait
    });

    test('旧版单模型 JSON 兼容加载到默认场景', () async {
      final dir = await Directory.systemTemp.createTemp('knowpic_test');
      final store = MetadataStore(dir);
      await store.init();
      final legacy = PreferenceModel(dim: 4);
      legacy.update([1.0, 0.0, 0.0, 0.0], 1.0, 1.0);
      final metaDir = Directory('${dir.path}/${AppConfig.rootDirName}');
      await File('${metaDir.path}/${AppConfig.userPrefFile}')
          .writeAsString(jsonEncode(legacy.toJson()));
      final store2 = MetadataStore(dir);
      await store2.init();
      expect(store2.preferences[AppConfig.defaultScene], isNotNull);
      expect(store2.preferences[AppConfig.defaultScene]!.sampleCount, greaterThan(0));
      expect(store2.preferences[AppConfig.defaultScene]!.dim, 4);
    });

    test('排序使用场景独立偏好模型', () async {
      final dir = await Directory.systemTemp.createTemp('knowpic_test');
      final store = MetadataStore(dir);
      await store.init();
      // 训练风景模型：偏好特征[0]
      final land = store.scenePreference(AppConfig.sceneLandscape);
      final posF = Float32List(AppConfig.featureDim);
      posF[0] = 1.0;
      final negF = Float32List(AppConfig.featureDim);
      negF[1] = 1.0;
      for (var i = 0; i < 5; i++) {
        land.updatePair(posF.toList(), negF.toList(), 1.0);
      }
      expect(land.isTrained, isTrue);

      final ranking = RankingService(LearningService(store));
      final a = _asset('a', sceneType: AppConfig.sceneLandscape, baseScore: 5, features: posF);
      final b = _asset('b', sceneType: AppConfig.sceneLandscape, baseScore: 5, features: negF);
      final members = [b, a];
      final sorted = ranking.sortGroup(members);
      expect(sorted.first.id, 'a', reason: '风景模型偏好特征[0]，a 应排前');
      // 其他场景模型未训练 → 冷启动，不应影响风景组排序
      expect(store.preferences[AppConfig.scenePortrait], isNull);
    });
  });

  group('MemoryService', () {
    test('盲盒只抽 90 天前的旧照', () {
      final old = _asset('old', created: DateTime.now().subtract(const Duration(days: 200)));
      final recent = _asset('recent', created: DateTime.now().subtract(const Duration(days: 10)));
      final picked = MemoryService.pickBlindBox({'old': old, 'recent': recent}, count: 1);
      expect(picked, hasLength(1));
      expect(picked.first.id, 'old');
    });

    test('那年今日匹配月日忽略年份', () {
      final match = _asset('match', created: DateTime(2020, 9, 5, 10, 0));
      final now = DateTime(2026, 9, 5, 8, 0);
      final photos = MemoryService.todayInHistory({'match': match}, now);
      expect(photos.map((p) => p.id), contains('match'));
    });
  });

  group('UserAction 权重', () {
    test('放大/收藏为强正样本', () {
      final zoom = UserAction(assetId: 'a', groupId: 'g', type: ActionType.zoomIn, timestamp: DateTime.now());
      final fav = UserAction(assetId: 'a', groupId: 'g', type: ActionType.favorite, timestamp: DateTime.now());
      expect(zoom.isPositive, isTrue);
      expect(zoom.weight, AppConfig.strongPositiveWeight);
      expect(fav.weight, AppConfig.strongPositiveWeight);
    });

    test('快速划走为负样本', () {
      final short = UserAction(assetId: 'a', groupId: 'g', type: ActionType.viewShort, timestamp: DateTime.now());
      expect(short.isPositive, isFalse);
    });
  });
}
