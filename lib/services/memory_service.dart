import 'dart:math' as math;

import '../core/utils/time_utils.dart';
import '../models/photo_asset.dart';

/// 记忆盲盒 & 那年今日（对应文档 Phase 3：记忆盲盒 / 那年今日）
class MemoryService {
  MemoryService._();

  static final _rand = _SeededRandom();

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

/// 简单可播种随机源（无需外部依赖）
class _SeededRandom implements math.Random {
  int _state = DateTime.now().microsecondsSinceEpoch & 0x7fffffff;

  @override
  int nextInt(int max) {
    _state = (_state * 1103515245 + 12345) & 0x7fffffff;
    return _state % max;
  }

  @override
  double nextDouble() => nextInt(0x3fffffff) / 0x3fffffff;

  @override
  bool nextBool() => nextInt(2) == 0;
}
