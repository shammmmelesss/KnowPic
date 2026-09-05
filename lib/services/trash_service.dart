import 'dart:io';

import '../core/constants.dart';
import '../core/logger.dart';
import '../models/photo_asset.dart';
import '../models/trash_item.dart';
import 'metadata_store.dart';
import 'photo_library_service.dart';

/// 清理结果
class TrashResult {
  const TrashResult({
    required this.trashedCount,
    required this.skippedIds,
    required this.failedIds,
    required this.freedBytes,
  });

  final int trashedCount;
  final List<String> skippedIds; // 云占位符等无法备份
  final List<String> failedIds; // 系统删除失败
  final int freedBytes;
}

/// 回收站与安全机制（对应文档 7.6 SafetyService）
/// 软删除 = 原图备份到应用回收站目录 + 从系统相册删除；30 天后物理清理。
class TrashService {
  TrashService(this._store, this._library);

  final MetadataStore _store;
  final PhotoLibraryService _library;

  /// 软删除：备份原图 → 移入回收站 → 从系统相册删除
  Future<TrashResult> softDelete(
    List<String> ids,
    Map<String, PhotoAsset> byId,
  ) async {
    final trashed = <TrashItem>[];
    final skipped = <String>[];
    var freed = 0;

    for (final id in ids) {
      final asset = byId[id];
      if (asset == null) {
        skipped.add(id);
        continue;
      }
      // 云占位符等无法取回原图 → 跳过并提示（文档 12.1）
      final bytes = await _library.loadOriginalBytes(id);
      if (bytes == null || bytes.isEmpty) {
        skipped.add(id);
        Log.d('Trash', 'skip $id (no local data)');
        continue;
      }
      final ext = _safeExt(asset.title);
      final fileName = '${id}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File('${_store.trashDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      final deletedAt = DateTime.now();
      trashed.add(TrashItem(
        id: id,
        originalTitle: asset.title.isEmpty ? fileName : asset.title,
        savedFileName: fileName,
        byteSize: bytes.length,
        deletedAt: deletedAt,
        expiresAt: deletedAt.add(const Duration(days: AppConfig.trashRetentionDays)),
        isLivePhoto: asset.isLivePhoto,
      ));
      freed += bytes.length;
    }

    final toDelete = ids.where((id) => !skipped.contains(id)).toList();
    final failed = await _library.deleteAssets(toDelete);

    // 系统删除失败的：撤回收回站备份
    for (final id in failed) {
      final item = _findTrash(id);
      if (item != null) {
        final f = _store.trashFileOf(item);
        if (await f.exists()) await f.delete();
        trashed.remove(item);
        freed -= item.byteSize;
      }
    }

    _store.trashItems.addAll(trashed);
    await _store.saveTrash();
    Log.d('Trash', 'softDelete trashed=${trashed.length} skipped=${skipped.length} '
        'failed=${failed.length} freed=$freed');
    return TrashResult(
      trashedCount: trashed.length,
      skippedIds: skipped,
      failedIds: failed,
      freedBytes: freed,
    );
  }

  /// 还原：写回系统相册 → 删除本地备份
  Future<List<String>> restore(List<String> ids) async {
    final restored = <String>[];
    for (final id in ids) {
      final item = _findTrash(id);
      if (item == null) continue;
      final file = _store.trashFileOf(item);
      if (!await file.exists()) {
        _store.trashItems.remove(item);
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        final filename = '${_baseName(item.originalTitle)}.jpg';
        await _library.saveImageToAlbum(bytes, filename: filename, title: item.originalTitle);
        await file.delete();
        _store.trashItems.remove(item);
        restored.add(id);
      } catch (err) {
        Log.e('Trash', 'restore failed: $id', err);
      }
    }
    await _store.saveTrash();
    return restored;
  }

  /// 彻底删除（立即物理删除，不过回收站）
  Future<List<String>> permanentDelete(List<String> ids) async {
    final removed = <String>[];
    for (final id in ids) {
      final item = _findTrash(id);
      if (item == null) continue;
      final f = _store.trashFileOf(item);
      if (await f.exists()) await f.delete();
      _store.trashItems.remove(item);
      removed.add(id);
    }
    await _store.saveTrash();
    return removed;
  }

  /// 过期清理：启动时检查过期文件（30 天），物理删除（文档 7.6 realClean）
  Future<int> realClean() async {
    final expired = _store.trashItems.where((t) => t.isExpired).toList();
    for (final item in expired) {
      final f = _store.trashFileOf(item);
      if (await f.exists()) await f.delete();
      _store.trashItems.remove(item);
    }
    if (expired.isNotEmpty) {
      await _store.saveTrash();
    }
    return expired.length;
  }

  TrashItem? _findTrash(String id) {
    for (final t in _store.trashItems) {
      if (t.id == id) return t;
    }
    return null;
  }

  String _safeExt(String title) {
    final dot = title.lastIndexOf('.');
    if (dot > 0 && dot < title.length - 1) {
      final ext = title.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{3,4}$').hasMatch(ext)) return ext;
    }
    return 'jpg';
  }

  String _baseName(String title) {
    final dot = title.lastIndexOf('.');
    if (dot > 0) return title.substring(0, dot);
    return title.isEmpty ? 'restored' : title;
  }
}
