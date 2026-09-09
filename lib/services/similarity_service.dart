import '../core/constants.dart';
import '../core/logger.dart';
import '../core/utils/dhash.dart';
import '../models/group_type.dart';
import '../models/photo_asset.dart';
import '../models/similar_group.dart';

/// 聚类引擎（对应文档 7.2 SimilarityService）
/// 使用并查集（Union-Find）聚合 dHash 汉明距离 ≤ 阈值的照片，再按启发式分类组类型。
class SimilarityService {
  /// 聚合 + 分类
  List<SimilarGroup> clusterAndClassify(List<PhotoAsset> assets) {
    final clusters = _cluster(assets);
    final groups = <SimilarGroup>[];
    final byId = {for (final a in assets) a.id: a};
    var counter = 0;
    for (final memberIds in clusters) {
      if (memberIds.length < 2) continue; // 单张不成组
      final type = _classify(byId, memberIds);
      var totalBytes = 0;
      DateTime? rep;
      for (final id in memberIds) {
        final a = byId[id];
        totalBytes += a?.byteSize ?? 0;
        final t = a?.createdTime;
        if (t != null && (rep == null || t.isBefore(rep))) rep = t;
      }
      groups.add(SimilarGroup(
        groupId: 'g${counter++}',
        type: type,
        assetIds: List.of(memberIds),
        totalBytes: totalBytes,
        representativeTime: rep,
      ));
    }
    // 按代表时间降序（新的在前）
    groups.sort((a, b) {
      final ta = a.representativeTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.representativeTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    Log.d('Similarity', 'clusters=${clusters.length} groups=${groups.length}');
    return groups;
  }

  /// 并查集聚类，返回成员 id 列表的列表
  List<List<String>> _cluster(List<PhotoAsset> assets) {
    final n = assets.length;
    if (n == 0) return const [];
    final ids = assets.map((a) => a.id).toList();

    final parent = List<int>.generate(n, (i) => i);
    int find(int i) {
      while (parent[i] != i) {
        parent[i] = parent[parent[i]];
        i = parent[i];
      }
      return i;
    }

    void union(int a, int b) {
      final ra = find(a);
      final rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    // 预构建热点值：宽高比/长图标记/哈希均为 getter 或需重复计算，内层循环逐对调用代价高
    final aspects = List<double>.filled(n, 0);
    final longShots = List<bool>.filled(n, false);
    final hashes = List<int>.filled(n, 0);
    final sizes = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      final a = assets[i];
      aspects[i] = a.aspectRatio;
      longShots[i] = a.isLongShot;
      hashes[i] = a.dHash;
      sizes[i] = a.byteSize;
    }

    for (int i = 0; i < n; i++) {
      final ra = aspects[i];
      final li = longShots[i];
      final hi = hashes[i];
      final si = sizes[i];
      for (int j = i + 1; j < n; j++) {
        // 快速预过滤：宽高比不兼容（且非长图）或大小差异过大 → 不可能相似
        if (!li && !longShots[j] && (ra - aspects[j]).abs() > 0.25) continue;
        final sj = sizes[j];
        if ((si - sj).abs() > si * 0.6 + sj * 0.6) continue;
        if (PerceptualHash.hammingDistance(hi, hashes[j]) <=
            AppConfig.hammingThresholdGroup) {
          union(i, j);
        }
      }
    }

    final byRoot = <int, List<String>>{};
    for (int i = 0; i < n; i++) {
      byRoot.putIfAbsent(find(i), () => []).add(ids[i]);
    }
    return byRoot.values.toList();
  }

  /// 组类型启发式分类
  GroupType _classify(Map<String, PhotoAsset> byId, List<String> memberIds) {
    final members = memberIds.map((id) => byId[id]).whereType<PhotoAsset>().toList();
    if (members.isEmpty) return GroupType.mixed;

    // 长截图/全景图（文档 7.2 特殊处理）
    if (members.every((a) => a.isLongShot)) return GroupType.longShot;

    // 截图标题模式
    final allScreenshot = members.every((a) => _isScreenshotTitle(a.title));
    if (allScreenshot && members.length >= 2) return GroupType.screenshot;

    // 时间跨度
    final times = members.map((a) => a.createdTime.millisecondsSinceEpoch).toList()..sort();
    final span = times.last - times.first;

    // 成对 dHash 距离（最大/最小）
    var minD = 64;
    var maxD = 0;
    for (int i = 0; i < members.length; i++) {
      for (int j = i + 1; j < members.length; j++) {
        final d = PerceptualHash.hammingDistance(members[i].dHash, members[j].dHash);
        if (d < minD) minD = d;
        if (d > maxD) maxD = d;
      }
    }

    // 完全重复：同尺寸 + 大小接近 + 距离极小
    final sameSize = members.every((a) =>
        a.width == members.first.width && a.height == members.first.height);
    final sizeClose = members.every((a) =>
        (a.byteSize - members.first.byteSize).abs() <=
        members.first.byteSize * AppConfig.sizeTolerance);
    if (sameSize && sizeClose && maxD <= AppConfig.hammingThresholdDuplicate) {
      return GroupType.duplicate;
    }

    // 连拍：时间窗 ≤3s，距离较近
    if (span <= AppConfig.burstTimeWindowMs &&
        maxD <= AppConfig.hammingThresholdBurst) {
      return GroupType.burst;
    }

    // 修图稿：时间窗 ≤10min，同场景但经过编辑（距离允许更大）
    if (span <= AppConfig.editHistoryTimeWindowMs &&
        maxD <= AppConfig.hammingThresholdEdit) {
      return GroupType.editHistory;
    }

    return GroupType.mixed;
  }

  static bool _isScreenshotTitle(String title) {
    final t = title.toLowerCase();
    return t.contains('screenshot') ||
        t.contains('screen shot') ||
        t.contains('截屏') ||
        t.contains('截图') ||
        t.contains('屏幕快照') ||
        t.contains('wechat') ||
        t.contains('微信图片');
  }

  /// 计算一组照片的预估可释放空间（保留最佳，其余删除）
  int estimateReclaimable(SimilarGroup group, Map<String, PhotoAsset> byId) {
    if (group.bestId.isEmpty || group.assetIds.length < 2) return 0;
    final best = byId[group.bestId];
    final bestBytes = best?.byteSize ?? 0;
    return (group.totalBytes - bestBytes).clamp(0, group.totalBytes);
  }
}
