/// 时间工具（那年今日 / 记忆盲盒）
class TimeUtils {
  TimeUtils._();

  /// 一年中的第几天（用于"那年今日"匹配）
  static int dayOfYear(DateTime d) {
    final start = DateTime(d.year, 1, 1);
    return d.difference(start).inDays + 1;
  }

  /// 判断两张照片是否为同一天的"那年今日"（忽略年份，考虑闰年 2/29）
  static bool isSameMonthDay(DateTime a, DateTime b) {
    if (a.month == 2 && a.day == 29 && b.month == 2 && b.day == 29) return true;
    if (a.month == 2 && a.day == 29) return b.month == 2 && (b.day == 28 || b.day == 29);
    if (b.month == 2 && b.day == 29) return a.month == 2 && (a.day == 28 || a.day == 29);
    return a.month == b.month && a.day == b.day;
  }

  /// 是否为"历史旧照"（早于给定天数）
  static bool isOldPhoto(DateTime created, int olderThanDays) {
    return DateTime.now().difference(created).inDays > olderThanDays;
  }

  /// 剩余天数文案
  static String daysLabel(DateTime from, DateTime to) {
    final d = to.difference(from).inDays;
    return d > 0 ? '$d 天' : '今天到期';
  }
}
