import 'dart:math' as math;

import '../core/utils/time_utils.dart';
import '../models/photo_asset.dart';

/// 记忆盲盒 & 那年今日（对应文档 Phase 3：记忆盲盒 / 那年今日）
class MemoryService {
  MemoryService._();

  // 固定种子的 Random：仅用于盲盒洗牌（非安全用途），
  // 不再用自造 LCG（低位周期极短、取模分布偏斜）
  static final _rand = math.Random(0x5eed);

  /// 记忆盲盒：从历史旧照中随机抽取
  static List<PhotoAsset> pickBlindBox(
    Map<String, PhotoAsset> assets, {
    int count = 1,
    int olderThanDays = 90,
  }) {
    final pool = assets.values
        .where((a) => TimeUtils.isOldPhoto(a.createdTime, olderThanDays))
        .toList();
    if (pool.isEmpty) return const [];
    pool.shuffle(_rand);
    return pool.take(count).toList();
  }

  /// 那年今日：匹配今天月日的历史照片（不含今年）
  static List<PhotoAsset> todayInHistory(Map<String, PhotoAsset> assets, DateTime now) {
    final out = assets.values
        .where((a) =>
            a.createdTime.year < now.year &&
            TimeUtils.isSameMonthDay(a.createdTime, now))
        .toList()
      ..sort((a, b) => b.createdTime.compareTo(a.createdTime));
    return out;
  }
}

