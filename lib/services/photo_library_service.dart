import 'dart:math' as math;
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../core/constants.dart';
import '../core/logger.dart';
import '../models/photo_asset.dart';

/// 相册访问抽象（便于单元测试替换为内存实现）
abstract class PhotoLibraryService {
  Future<bool> requestPermission();

  /// 只读检查当前系统授权状态（不弹系统窗，用于冷启动恢复）
  Future<bool> checkPermission();

  bool get hasPermission;

  /// 加载全部图片资产（仅元数据，不加载像素）。
  /// 跳过视频与 iCloud 占位符（文档 12.1：禁止扫描时触发网络下载）。
  /// [newerThan] 非空时启用早停：相册按时间倒序分页，整页早于该时间即停止拉取
  /// （首页"最近照片"场景无需遍历全库）。
  Future<List<PhotoAsset>> loadAllPhotos({
    void Function(int done)? onProgress,
    DateTime? newerThan,
  });

  /// 加载缩略图（展示用 512；特征分析传 256，4× 解码/传输开销）
  Future<Uint8List?> loadThumbnail(String id, {int size = 512});

  /// 加载原图数据（用于回收站备份；iCloud 未下载会触发下载，故仅在用户操作时调用）
  Future<Uint8List?> loadOriginalBytes(String id);

  /// 从系统相册删除资产，返回删除失败的 id
  Future<List<String>> deleteAssets(List<String> ids);

  /// 将图片数据写回系统相册（回收站还原），返回新资产 id
  Future<String> saveImageToAlbum(Uint8List bytes, {required String filename, String? title});
}

/// photo_manager 实现（iOS 优先）
class PhotoManagerLibrary implements PhotoLibraryService {
  final Map<String, AssetEntity> _entities = {};
  bool _granted = false;

  @override
  Future<bool> requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    _granted = state == PermissionState.authorized || state == PermissionState.limited;
    Log.d('PhotoLibrary', 'permission=$state granted=$_granted');
    return _granted;
  }

  @override
  Future<bool> checkPermission() async {
    final state = await PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(),
    );
    _granted = state == PermissionState.authorized || state == PermissionState.limited;
    Log.d('PhotoLibrary', 'checkPermission=$state granted=$_granted');
    return _granted;
  }

  @override
  bool get hasPermission => _granted;

  @override
  Future<List<PhotoAsset>> loadAllPhotos({
    void Function(int done)? onProgress,
    DateTime? newerThan,
  }) async {
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
    );
    final entities = <AssetEntity>[];
    for (final path in paths) {
      int page = 0;
      while (true) {
        final pageAssets = await path.getAssetListPaged(
          page: page,
          size: AppConfig.scanPageSize,
        );
        if (pageAssets.isEmpty) break;
        entities.addAll(pageAssets);
        page++;
        // 早停：相册按创建时间倒序分页，整页都早于下界 → 后续页更旧，无需再拉
        if (newerThan != null &&
            pageAssets.every((e) => e.createDateTime.isBefore(newerThan))) {
          break;
        }
      }
    }

    // 去重 + 仅保留图片类型；有早停下界时直接跳过更旧的资产（不再探测平台通道）
    final seen = <String>{};
    final images = <AssetEntity>[];
    for (final e in entities) {
      if (e.type != AssetType.image) continue;
      if (!seen.add(e.id)) continue;
      if (newerThan != null && e.createDateTime.isBefore(newerThan)) continue;
      images.add(e);
    }

    // 分批并发探测：本地可用性与文件大小均为平台通道调用，串行太慢
    final cutoff = DateTime.now().add(const Duration(days: 1)); // 时间戳异常守卫（时钟漂移容忍 1 天）
    final photos = <PhotoAsset>[];
    var done = 0;
    final step = AppConfig.scanProbeConcurrency;
    for (var i = 0; i < images.length; i += step) {
      final chunk = images.sublist(i, math.min(i + step, images.length));
      final probed = await Future.wait(chunk.map((e) => _probeAsset(e, cutoff)));
      for (var j = 0; j < chunk.length; j++) {
        final asset = probed[j];
        if (asset != null) {
          photos.add(asset);
          _entities[asset.id] = chunk[j];
        }
        done++;
      }
      onProgress?.call(done);
    }
    Log.d('PhotoLibrary', 'loaded ${photos.length}/${images.length} local images');
    return photos;
  }

  /// 探测单个资产元数据。
  /// 仅收集本地已有文件的图片：先用 [AssetEntity.isLocallyAvailable] 守卫，
  /// 绝不在扫描阶段触发 iCloud 下载（文档 12.1）。
  Future<PhotoAsset?> _probeAsset(AssetEntity e, DateTime cutoff) async {
    try {
      // 时间戳异常（晚于当前时间+1天）→ 元数据不可信，跳过
      if (e.createDateTime.isAfter(cutoff)) return null;
      if (!await e.isLocallyAvailable()) return null; // iCloud 占位符 → 跳过
      final f = await e.file; // 本地已有，仅解析路径，不触发下载
      if (f == null) return null;
      final size = await f.length();
      if (size <= 0) return null;
      return PhotoAsset(
        id: e.id,
        title: e.title ?? '',
        width: e.width,
        height: e.height,
        byteSize: size,
        createdTime: e.createDateTime,
        isLivePhoto: e.isLivePhoto,
      );
    } catch (err) {
      Log.e('PhotoLibrary', 'probe failed: ${e.id}', err);
      return null;
    }
  }

  @override
  Future<Uint8List?> loadThumbnail(String id, {int size = 512}) async {
    final e = _entities[id];
    if (e == null) return null;
    try {
      return await e.thumbnailDataWithSize(
        ThumbnailSize(size, size),
        quality: AppConfig.thumbnailQuality,
      );
    } catch (err) {
      Log.e('PhotoLibrary', 'thumbnail failed: $id', err);
      return null;
    }
  }

  @override
  Future<Uint8List?> loadOriginalBytes(String id) async {
    final e = _entities[id];
    if (e == null) return null;
    try {
      return await e.originBytes;
    } catch (err) {
      Log.e('PhotoLibrary', 'originBytes failed: $id', err);
      return null;
    }
  }

  @override
  Future<List<String>> deleteAssets(List<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      final failed = await PhotoManager.editor.deleteWithIds(ids);
      Log.d('PhotoLibrary', 'delete ${ids.length - failed.length}/${ids.length}');
      return failed;
    } catch (err) {
      Log.e('PhotoLibrary', 'deleteWithIds failed', err);
      return ids;
    }
  }

  @override
  Future<String> saveImageToAlbum(
    Uint8List bytes, {
    required String filename,
    String? title,
  }) async {
    final e = await PhotoManager.editor.saveImage(
      bytes,
      filename: filename,
      title: title ?? filename,
    );
    _entities[e.id] = e;
    return e.id;
  }
}
