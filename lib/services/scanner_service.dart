import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../core/constants.dart';
import '../core/logger.dart';
import '../core/utils/dhash.dart';
import '../core/utils/image_features.dart';
import '../models/photo_asset.dart';
import '../models/scan_progress.dart';
import 'metadata_store.dart';
import 'photo_library_service.dart';
import 'ranking_service.dart';
import 'similarity_service.dart';

/// 扫描结果统计
class ScanResult {
  const ScanResult({
    required this.totalPhotos,
    required this.analyzedPhotos,
    required this.groups,
    required this.elapsedMs,
  });

  final int totalPhotos;
  final int analyzedPhotos;
  final int groups;
  final int elapsedMs;
}

/// 隔离区单张分析结果
class _PhotoAnalysis {
  const _PhotoAnalysis(this.dHash, this.analysis);

  final int dHash;
  final ImageAnalysis analysis;
}

/// 扫描调度器（对应文档 7.1 ScannerService）
/// 流水线：IO 拉取缩略图（主隔离区）→ CPU 特征提取（Isolate）→ 聚类 → 持久化。
class ScannerService {
  ScannerService({
    required this._library,
    required this._store,
    required this._similarity,
    required this._ranking,
  });

  final PhotoLibraryService _library;
  final MetadataStore _store;
  final SimilarityService _similarity;
  final RankingService _ranking;

  final ValueNotifier<ScanProgress> progress = ValueNotifier(const ScanProgress());
  bool _running = false;
  bool get isRunning => _running;

  /// 全量扫描
  Future<ScanResult> fullScan() => _scan(incremental: false);

  /// 增量扫描：仅分析新增照片（文档 Phase 2 增量扫描）
  Future<ScanResult> incrementalScan() => _scan(incremental: true);

  Future<ScanResult> _scan({required bool incremental}) async {
    if (_running) throw StateError('scan already running');
    _running = true;
    final sw = Stopwatch()..start();
    try {
      progress.value = const ScanProgress(phase: ScanPhase.reading, message: '正在读取相册…');

      final photos = await _library.loadAllPhotos(onProgress: (done) {
        progress.value = progress.value.copyWith(current: done, message: '正在读取相册（$done）…');
      });

      final currentIds = {for (final p in photos) p.id};
      // 已从系统相册移除的资产清理
      final removed = _store.assets.keys.where((id) => !currentIds.contains(id)).toList();
      for (final id in removed) {
        _store.assets.remove(id);
      }

      // 需要分析的照片：全量=全部；增量=新增
      final toAnalyze = incremental
          ? photos.where((p) => !_store.assets.containsKey(p.id)).toList()
          : photos;

      final merged = <String, PhotoAsset>{};
      if (incremental) {
        // 保留已有资产及其特征
        merged.addEntries(_store.assets.entries);
        for (final p in photos) {
          merged[p.id] = p; // 刷新元数据（可能已变更）
        }
      } else {
        for (final p in photos) {
          merged[p.id] = p;
        }
      }

      if (toAnalyze.isNotEmpty) {
        progress.value = ScanProgress(
          phase: ScanPhase.analyzing,
          total: toAnalyze.length,
          message: '正在提取特征…',
        );
        var done = 0;
        for (final batch in _chunks(toAnalyze, AppConfig.batchSize)) {
          final thumbnails = await Future.wait(
            batch.map((p) => _library.loadThumbnail(p.id)),
          );
          final validBytes = <Uint8List>[];
          final validPhotos = <PhotoAsset>[];
          for (var i = 0; i < batch.length; i++) {
            final bytes = thumbnails[i];
            if (bytes == null || bytes.isEmpty) continue;
            validBytes.add(bytes);
            validPhotos.add(batch[i]);
          }
          final analyses = await _analyzeBatch(validBytes);
          for (var i = 0; i < validPhotos.length && i < analyses.length; i++) {
            final p = validPhotos[i];
            final a = analyses[i];
            merged[p.id] = p.copyWith(
              dHash: a.dHash,
              features: a.analysis.features,
              baseScore: a.analysis.aestheticScore,
              sceneType: a.analysis.sceneType,
            );
          }
          done += batch.length;
          progress.value = progress.value.copyWith(
            current: done,
            message: '正在提取特征（$done/${toAnalyze.length}）…',
          );
        }
      }

      progress.value = const ScanProgress(phase: ScanPhase.clustering, message: '正在聚类分组…');
      final allAssets = merged.values.toList();
      final groups = _similarity.clusterAndClassify(allAssets);

      // AI 推荐：每组选出"最佳"并计算综合分
      final byId = merged;
      for (final g in groups) {
        final members = g.assetIds.map((id) => byId[id]).whereType<PhotoAsset>().toList();
        g.bestId = _ranking.pickBest(members) ?? '';
      }

      progress.value = const ScanProgress(phase: ScanPhase.saving, message: '正在保存…');
      await _store.replaceAll(allAssets, groups);

      sw.stop();
      progress.value = ScanProgress(
        phase: ScanPhase.done,
        current: toAnalyze.length,
        total: toAnalyze.length,
        message: '扫描完成',
        elapsedMs: sw.elapsedMilliseconds,
      );
      Log.d('Scanner', 'scan done in ${sw.elapsedMilliseconds}ms '
          'photos=${allAssets.length} groups=${groups.length}');
      return ScanResult(
        totalPhotos: photos.length,
        analyzedPhotos: toAnalyze.length,
        groups: groups.length,
        elapsedMs: sw.elapsedMilliseconds,
      );
    } catch (err) {
      progress.value = const ScanProgress(phase: ScanPhase.failed, message: '扫描失败');
      Log.e('Scanner', 'scan failed', err);
      rethrow;
    } finally {
      _running = false;
    }
  }

  /// 偏好更新后重新排序（无需重新扫描）
  Future<void> refreshScores() async {
    final byId = _store.assets;
    for (final g in _store.groups) {
      final members = g.assetIds.map((id) => byId[id]).whereType<PhotoAsset>().toList();
      g.bestId = _ranking.pickBest(members) ?? g.bestId;
    }
    await _store.saveGroups();
  }

  /// 批量分析：在独立 Isolate 中解码 + dHash + 128 维特征 + 美学分
  Future<List<_PhotoAnalysis>> _analyzeBatch(List<Uint8List> thumbnails) async {
    if (thumbnails.isEmpty) return const [];
    try {
      return await Isolate.run(() => _analyzePhotos(thumbnails));
    } catch (err) {
      Log.e('Scanner', 'isolate analyze failed, fallback to main isolate', err);
      return _analyzePhotos(thumbnails);
    }
  }

  List<List<T>> _chunks<T>(List<T> list, int size) {
    if (size <= 0) return [list];
    final out = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      out.add(list.sublist(i, i + size > list.length ? list.length : i + size));
    }
    return out;
  }
}

/// 供 Isolate.run 调用的顶层函数（纯 Dart，可跨隔离区传输）
List<_PhotoAnalysis> _analyzePhotos(List<Uint8List> thumbnails) {
  final out = <_PhotoAnalysis>[];
  for (final bytes in thumbnails) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) continue;
      final analysis = ImageFeatures.analyze(decoded);
      final dHash = PerceptualHash.dHash(decoded);
      out.add(_PhotoAnalysis(dHash, analysis));
    } catch (err) {
      debugPrint('analyze photo failed: $err');
    }
  }
  return out;
}
