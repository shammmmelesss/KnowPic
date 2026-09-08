import 'dart:io';
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
  Future<List<PhotoAsset>> loadAllPhotos({void Function(int done)? onProgress});

  Future<Uint8List?> loadThumbnail(String id);

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
  Future<List<PhotoAsset>> loadAllPhotos({void Function(int done)? onProgress}) async {
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
      }
    }

    final seen = <String>{};
    final photos = <PhotoAsset>[];
    var done = 0;
    for (final e in entities) {
      done++;
      if (!seen.add(e.id)) {
        onProgress?.call(done);
        continue;
      }
      if (e.type != AssetType.image) {
        onProgress?.call(done);
        continue;
      }
      // iCloud 占位符检测：本地无文件则跳过（文档 12.1）
      File? f;
      try {
        f = await e.file;
      } catch (err) {
        Log.e('PhotoLibrary', 'file fetch failed: ${e.id}', err);
        onProgress?.call(done);
        continue;
      }
      if (f == null) {
        onProgress?.call(done);
        continue;
      }
      photos.add(PhotoAsset(
        id: e.id,
        title: e.title ?? '',
        width: e.width,
        height: e.height,
        byteSize: f.lengthSync(),
        createdTime: e.createDateTime,
        isLivePhoto: e.isLivePhoto,
      ));
      _entities[e.id] = e;
      onProgress?.call(done);
    }
    return photos;
  }

  @override
  Future<Uint8List?> loadThumbnail(String id) async {
    final e = _entities[id];
    if (e == null) return null;
    try {
      return await e.thumbnailDataWithSize(
        const ThumbnailSize(512, 512),
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
