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
    final skippedSet = <String>{};
    var freed = 0;
    var seq = 0;

    for (final id in ids) {
      final asset = byId[id];
      if (asset == null) {
        skipped.add(id);
        skippedSet.add(id);
        continue;
      }
      final ext = _safeExt(asset.title);
      // 序号进文件名：同一毫秒内批量删除不会产生重名
      // （重名会让后写的备份覆盖先写的，还原时拿回错误的照片）
      final fileName =
          '${_safeId(id)}_${DateTime.now().millisecondsSinceEpoch}_$seq.$ext';
      seq++;
      final deletedAt = DateTime.now();
      final item = TrashItem(
        id: id,
        originalTitle: asset.title.isEmpty ? fileName : asset.title,
        savedFileName: fileName,
        byteSize: asset.byteSize,
        deletedAt: deletedAt,
        expiresAt: deletedAt.add(const Duration(days: AppConfig.trashRetentionDays)),
        isLivePhoto: asset.isLivePhoto,
      );
      // 写入路径统一走 trashFileOf（内部做文件名消毒，防路径穿越）。
      // 流式拷贝：原图不整块读入内存，避免大图批量清理时 OOM。
      final copied =
          await _library.copyOriginalToFile(id, _store.trashFileOf(item));
      if (!copied) {
        // 云占位符等无法取回原图 → 跳过并提示（文档 12.1）
        skipped.add(id);
        skippedSet.add(id);
        Log.d('Trash', 'skip ${_short(id)} (no local data)');
        continue;
      }
      trashed.add(item);
      freed += asset.byteSize;
    }

    final toDelete = ids.where((id) => !skippedSet.contains(id)).toList();
    final failed = await _library.deleteAssets(toDelete);

    // 系统删除失败的：撤回收回站备份
    final trashedById = {for (final t in trashed) t.id: t};
    for (final id in failed) {
      final item = trashedById[id];
      if (item == null) continue;
      final f = _store.trashFileOf(item);
      if (await f.exists()) await f.delete();
      trashed.remove(item);
      freed -= item.byteSize;
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
    final byId = {for (final t in _store.trashItems) t.id: t};
    final restored = <String>[];
    for (final id in ids) {
      final item = byId[id];
      if (item == null) continue;
      final file = _store.trashFileOf(item);
      if (!await file.exists()) {
        _store.trashItems.remove(item);
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        // 还原为备份时的真实扩展名（而非硬编码 .jpg）
        final filename = '${_baseName(item.originalTitle)}${_extOf(item.savedFileName)}';
        await _library.saveImageToAlbum(bytes, filename: filename, title: item.originalTitle);
        await file.delete();
        _store.trashItems.remove(item);
        restored.add(id);
      } catch (err) {
        Log.e('Trash', 'restore failed: ${_short(id)}', err);
      }
    }
    await _store.saveTrash();
    return restored;
  }

  /// 彻底删除（立即物理删除，不过回收站）
  Future<List<String>> permanentDelete(List<String> ids) async {
    final byId = {for (final t in _store.trashItems) t.id: t};
    final removed = <String>[];
    for (final id in ids) {
      final item = byId[id];
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
    // 对账：清掉 manifest 里没有记录的孤儿备份文件
    // （备份写盘成功、manifest 尚未写入时崩溃 → 文件永远不会被回收）
    await _store.cleanOrphanTrashFiles();
    if (expired.isNotEmpty) {
      await _store.saveTrash();
    }
    return expired.length;
  }

  /// 资产 id 属于相册内部标识，日志只保留前 8 位
  static String _short(String id) =>
      id.length <= 8 ? id : '${id.substring(0, 8)}…';

  /// 资产 id 仅保留安全字符，避免拼进文件名后产生路径穿越
  String _safeId(String id) {
    final s = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return s.isEmpty ? 'a' : s;
  }

  String _safeExt(String title) {
    final dot = title.lastIndexOf('.');
    if (dot > 0 && dot < title.length - 1) {
      final ext = title.substring(dot + 1).toLowerCase();
      if (RegExp(r'^[a-z0-9]{3,4}$').hasMatch(ext)) return ext;
    }
    return 'jpg';
  }

  /// 从备份文件名提取扩展名（带点），校验失败时兜底 .jpg
  String _extOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '.jpg';
    final ext = fileName.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext) ? '.$ext' : '.jpg';
  }

  /// 还原文件名基础部分：剔除路径分隔符与扩展名，防注入
  String _baseName(String title) {
    var t = title.replaceAll(RegExp(r'[/\\]'), '_').trim();
    if (t.isEmpty) return 'restored';
    final dot = t.lastIndexOf('.');
    if (dot > 0) return t.substring(0, dot);
    return t;
  }
}
