import '../core/logger.dart';
import '../models/group_type.dart';
import '../models/photo_asset.dart';
import '../models/scan_report.dart';
import '../models/similar_group.dart';
import 'metadata_store.dart';

/// 空间释放报告（对应文档 9.5 清理报告 / 13.2 埋点指标）
class ReportService {
  ReportService(this._store);

  final MetadataStore _store;

  int _freedBytes = 0;
  int _deletedCount = 0;
  int _keptCount = 0;
  int _groupCount = 0;
  final Map<GroupType, int> _categoryCounts = {};
  final Set<String> _cleanedGroups = {};

  bool get hasSession => _cleanedGroups.isNotEmpty || _deletedCount > 0;

  /// 记录一组照片的清理结果（幂等：同一组只记一次）
  void recordClean(
    SimilarGroup group,
    List<String> keptIds,
    List<String> deletedIds,
    Map<String, PhotoAsset> byId,
  ) {
    if (!_cleanedGroups.add(group.groupId)) return;
    _groupCount++;
    _keptCount += keptIds.length;
    _deletedCount += deletedIds.length;
    for (final id in deletedIds) {
      _freedBytes += byId[id]?.byteSize ?? 0;
    }
    _categoryCounts[group.type] = (_categoryCounts[group.type] ?? 0) + 1;
  }

  /// 汇总并保存本次清理报告
  Future<CleanReport?> finalize() async {
    if (!hasSession) return null;
    final report = CleanReport(
      id: 'r${DateTime.now().millisecondsSinceEpoch}',
      createdAt: DateTime.now(),
      freedBytes: _freedBytes,
      deletedCount: _deletedCount,
      keptCount: _keptCount,
      groupCount: _groupCount,
      categoryCounts: Map.of(_categoryCounts),
    );
    _store.reports.insert(0, report);
    await _store.saveReports();
    reset();
    Log.d('Report', 'finalize freed=${report.freedLabel} deleted=${report.deletedCount}');
    return report;
  }

  /// 放弃本次会话（未执行清理）
  void reset() {
    _freedBytes = 0;
    _deletedCount = 0;
    _keptCount = 0;
    _groupCount = 0;
    _categoryCounts.clear();
    _cleanedGroups.clear();
  }
}
