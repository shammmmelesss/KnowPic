import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/constants.dart';
import '../core/logger.dart';
import '../models/photo_asset.dart';
import '../models/preference_model.dart';
import '../models/scan_report.dart';
import '../models/similar_group.dart';
import '../models/trash_item.dart';

/// 元数据存储（对应文档 6.1 文件目录结构）
/// - assets.json: 资产元数据（id/标题/尺寸/时间/哈希/分数）
/// - features_128.bin: 128 维特征向量池（float32 小端，每张 512 字节，mmap 读取）
/// - groups.json / user_pref.json / manifest.json / reports.json
class MetadataStore {
  MetadataStore(this.rootDir) {
    metaDir = Directory('${rootDir.path}/${AppConfig.rootDirName}');
    trashDir = Directory('${metaDir.path}/${AppConfig.trashDirName}');
  }

  final Directory rootDir;
  late final Directory metaDir;
  late final Directory trashDir;

  final Map<String, PhotoAsset> assets = {}; // id -> asset
  final List<SimilarGroup> groups = [];
  final List<TrashItem> trashItems = [];
  final List<CleanReport> reports = [];

  /// 持久化数据「降级加载」标志：文件里有无法解析的脏记录时置位。
  /// 置位期间禁止回写，否则会用残缺数据覆盖完好的文件（用户数据永久丢失），
  /// 直到一次全量扫描 replaceAll 重建后才解除。
  bool _degradedAssets = false;
  bool _degradedGroups = false;
  bool _degradedTrash = false;
  bool _degradedReports = false;

  bool get isDegraded =>
      _degradedAssets || _degradedGroups || _degradedTrash || _degradedReports;

  /// 多场景偏好模型：sceneType -> PreferenceModel（文档 8.1）
  /// 除各场景独立模型外，维护一个 'all' 全局汇总模型。
  late Map<String, PreferenceModel> preferences;

  String get _assetsPath => '${metaDir.path}/${AppConfig.assetsFile}';
  String get _featuresPath => '${metaDir.path}/${AppConfig.featuresFile}';
  String get _groupsPath => '${metaDir.path}/${AppConfig.groupsFile}';
  String get _prefPath => '${metaDir.path}/${AppConfig.userPrefFile}';
  String get _trashManifestPath => '${trashDir.path}/${AppConfig.trashManifestFile}';
  String get _reportsPath => '${metaDir.path}/${AppConfig.reportsFile}';

  /// 偏好模型文件（导出用）
  File get prefFile => File(_prefPath);

  /// 大 JSON 数组文件超过此大小即在隔离区解码，避免阻塞冷启动 UI
  static const int _jsonIsolateThreshold = 256 * 1024;

  /// 读取 JSON 数组文件（不存在返回 null）；大文件在隔离区 utf8 解码 + jsonDecode
  Future<List<Map<String, dynamic>>?> _readJsonList(String path) async {
    final f = File(path);
    if (!await f.exists()) return null;
    try {
      final bytes = await f.readAsBytes();
      if (bytes.length < _jsonIsolateThreshold) {
        return (jsonDecode(utf8.decode(bytes)) as List<dynamic>)
            .cast<Map<String, dynamic>>();
      }
      return await Isolate.run(
        () => (jsonDecode(utf8.decode(bytes)) as List<dynamic>)
            .cast<Map<String, dynamic>>(),
      );
    } catch (err) {
      // 只打文件名，不泄露完整沙盒路径
      Log.e('Store', 'read json failed: ${_leaf(path)}', err);
      return null;
    }
  }

  /// 路径脱敏：日志只保留最后一段（完整路径含 App UUID）
  static String _leaf(String path) => path.split(Platform.pathSeparator).last;

  /// 初始化目录并加载所有持久化数据
  Future<void> init() async {
    if (!await metaDir.exists()) await metaDir.create(recursive: true);
    if (!await trashDir.exists()) await trashDir.create(recursive: true);
    preferences = {AppConfig.defaultScene: PreferenceModel()};
    await _loadAssets();
    await _loadGroups();
    await _loadPref();
    await _loadTrash();
    await _loadReports();
    Log.d('Store', 'loaded assets=${assets.length} groups=${groups.length} '
        'trash=${trashItems.length} reports=${reports.length}');
  }

  // ---- 资产 ----

  Future<void> _loadAssets() async {
    final raw = await _readJsonList(_assetsPath);
    if (raw == null) return;
    // 逐条解析：单条脏记录只丢弃自己，不能让整批加载中断
    // （中断会导致 assets 只剩前半部分，下次回写就会覆盖掉完好的原文件）
    final parsed = <PhotoAsset>[];
    var skipped = 0;
    for (final e in raw) {
      try {
        parsed.add(PhotoAsset.fromJson(e));
      } catch (err) {
        skipped++;
        if (skipped <= 3) Log.e('Store', 'bad asset record skipped', err);
      }
    }
    assets
      ..clear()
      ..addEntries(parsed.map((a) => MapEntry(a.id, a)));
    if (skipped > 0) {
      _degradedAssets = true;
      Log.e('Store',
          'assets.json degraded: $skipped/${raw.length} bad records, write-back disabled');
    }
    try {
      await _loadFeatures();
    } catch (err) {
      Log.e('Store', 'load features failed', err);
    }
  }

  Future<void> _loadFeatures() async {
    final f = File(_featuresPath);
    if (!await f.exists()) return;
    final data = await f.readAsBytes();
    final dim = AppConfig.featureDim;
    final rowBytes = dim * 4;
    final count = data.length ~/ rowBytes;
    if (count == 0) return;
    final sortedIds = assets.keys.toList()..sort();
    // 配对守卫：特征行数必须与资产数一致，且文件没有截断（字节数足够覆盖所有行），
    // 否则按 id 排序配对会整体错位或 sublistView 越界
    // （正常由原子写保证；不一致说明文件损坏/半写，放弃配对等下次扫描重建）
    if (count != sortedIds.length || data.length < count * rowBytes) {
      Log.e('Store',
          'features.bin rows($count)!=assets(${sortedIds.length}) or '
          'truncated(${data.length} bytes), skip pairing');
      return;
    }
    for (int i = 0; i < count; i++) {
      final slice = Float32List.sublistView(
          data, i * dim * 4, (i + 1) * dim * 4);
      assets[sortedIds[i]]!.features = slice;
    }
  }

  /// 全量保存资产 + 特征（原子写：.tmp → rename，避免半写损坏）
  Future<void> saveAssets() async {
    if (_degradedAssets) {
      Log.e('Store', 'assets.json degraded, refuse overwrite (rescan to rebuild)');
      return;
    }
    final sorted = assets.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    // 先在主隔离区做轻量映射（避免发送复杂对象），重活（jsonEncode + float 编码）放隔离区
    final jsonMaps = sorted.map((a) => a.toJson()).toList();
    final featureLists = sorted.map((a) => a.features).toList();

    final (jsonBytes, featureBytes) =
        sorted.length >= AppConfig.storeIsolateThreshold
            ? await Isolate.run(() => _encodeAssetsPayload(jsonMaps, featureLists))
            : _encodeAssetsPayload(jsonMaps, featureLists);
    await _atomicWrite(_assetsPath, jsonBytes);
    await _atomicWrite(_featuresPath, featureBytes);
  }

  /// 编码资产 JSON 与特征二进制（float32 小端）。纯函数，可在隔离区运行。
  static (Uint8List, Uint8List) _encodeAssetsPayload(
    List<Map<String, dynamic>> jsonMaps,
    List<Float32List> featureLists,
  ) {
    final jsonBytes = utf8.encode(jsonEncode(jsonMaps));
    final dim = AppConfig.featureDim;
    final out = Float32List(jsonMaps.length * dim);
    var offset = 0;
    for (final f in featureLists) {
      final n = f.length < dim ? f.length : dim;
      if (n > 0) out.setRange(offset, offset + n, f);
      offset += dim;
    }
    // Flutter 目标平台均为小端，直接按内存布局导出；大端环境退回逐值编码
    final featureBytes = Endian.host == Endian.little
        ? out.buffer.asUint8List()
        : _float32ToLittleEndianBytes(out);
    return (jsonBytes, featureBytes);
  }

  static Uint8List _float32ToLittleEndianBytes(Float32List values) {
    final bd = ByteData(values.length * 4);
    for (var i = 0; i < values.length; i++) {
      bd.setFloat32(i * 4, values[i], Endian.little);
    }
    return bd.buffer.asUint8List();
  }

  /// 原子写入：先写同目录 .tmp 并 flush，再 rename 覆盖目标文件
  Future<void> _atomicWrite(String path, List<int> bytes) async {
    final tmp = File('$path.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(path);
  }

  Future<void> _atomicWriteString(String path, String data) =>
      _atomicWrite(path, utf8.encode(data));

  /// 替换全部资产与分组（扫描完成后调用）
  Future<void> replaceAll(List<PhotoAsset> newAssets, List<SimilarGroup> newGroups) async {
    assets
      ..clear()
      ..addEntries(newAssets.map((a) => MapEntry(a.id, a)));
    groups
      ..clear()
      ..addAll(newGroups);
    // 全量重建 → 解除降级锁定，允许回写
    _degradedAssets = false;
    _degradedGroups = false;
    await saveAssets();
    await saveGroups();
  }

  Float32List? assetFeatures(String id) => assets[id]?.features;

  // ---- 分组 ----

  Future<void> _loadGroups() async {
    final raw = await _readJsonList(_groupsPath);
    if (raw == null) return;
    final parsed = <SimilarGroup>[];
    var skipped = 0;
    for (final e in raw) {
      try {
        parsed.add(SimilarGroup.fromJson(e));
      } catch (err) {
        skipped++;
        if (skipped <= 3) Log.e('Store', 'bad group record skipped', err);
      }
    }
    groups
      ..clear()
      ..addAll(parsed);
    if (skipped > 0) {
      _degradedGroups = true;
      Log.e('Store',
          'groups.json degraded: $skipped/${raw.length} bad records, write-back disabled');
    }
  }

  Future<void> saveGroups() async {
    if (_degradedGroups) {
      Log.e('Store', 'groups.json degraded, refuse overwrite (rescan to rebuild)');
      return;
    }
    await _atomicWriteString(
      _groupsPath,
      jsonEncode(groups.map((g) => g.toJson()).toList()),
    );
  }

  // ---- 偏好 ----

  /// 取指定场景的偏好模型（不存在则新建，冷启动返回全 0.5 权重模型）
  PreferenceModel scenePreference(String sceneType) {
    final key = sceneType.isEmpty ? AppConfig.sceneOther : sceneType;
    final m = preferences[key];
    if (m != null) return m;
    final created = PreferenceModel();
    preferences[key] = created;
    return created;
  }

  Future<void> _loadPref() async {
    final f = File(_prefPath);
    preferences = {AppConfig.defaultScene: PreferenceModel()};
    if (!await f.exists()) return;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      final scenes = json['scenes'];
      if (scenes is Map<String, dynamic>) {
        scenes.forEach((k, v) {
          preferences[k] = PreferenceModel.fromJson(v as Map<String, dynamic>);
        });
      } else {
        // 旧版单模型格式：归入默认场景，兼容升级
        preferences[AppConfig.defaultScene] = PreferenceModel.fromJson(json);
      }
    } catch (err) {
      Log.e('Store', 'load pref failed', err);
    }
  }

  Future<void> savePref() async {
    await _atomicWriteString(
      _prefPath,
      jsonEncode({
        'scenes': preferences.map((k, v) => MapEntry(k, v.toJson())),
      }),
    );
  }

  // ---- 回收站 ----

  Future<void> _loadTrash() async {
    final raw = await _readJsonList(_trashManifestPath);
    if (raw == null) return;
    final parsed = <TrashItem>[];
    var skipped = 0;
    for (final e in raw) {
      try {
        parsed.add(TrashItem.fromJson(e));
      } catch (err) {
        skipped++;
        if (skipped <= 3) Log.e('Store', 'bad trash record skipped', err);
      }
    }
    trashItems
      ..clear()
      ..addAll(parsed);
    if (skipped > 0) {
      // manifest 残缺时不能删「孤儿文件」：那些文件可能正属于丢失的条目
      _degradedTrash = true;
      Log.e('Store',
          'manifest.json degraded: $skipped/${raw.length} bad records, orphan cleanup disabled');
    }
  }

  Future<void> saveTrash() async {
    await _atomicWriteString(
      _trashManifestPath,
      jsonEncode(trashItems.map((t) => t.toJson()).toList()),
    );
  }

  /// 回收站备份文件路径。
  /// 文件名来自 manifest.json（可能被篡改/损坏），这里强制消毒为纯文件名防路径穿越。
  File trashFileOf(TrashItem item) {
    // 白名单消毒：文件名来自 manifest.json（可能被损坏/篡改），
    // 分隔符与非法字符统一替换为 '_'，而不是删除 —— 删除会让不同名字收敛成同一个
    // （如 a..b.jpg 与 ab.jpg），导致两张照片的备份互相覆盖。
    var name = item.savedFileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    name = name.replaceFirst(RegExp(r'^\.+'), ''); // 不允许隐藏文件名
    name = name.replaceAll('..', '_'); // 双点：既防穿越也防与上一条重名
    if (name.isEmpty || name == '.' || name == '_') name = 'orphan.bin';
    return File('${trashDir.path}${Platform.pathSeparator}$name');
  }

  /// 清理回收站孤儿文件：磁盘上有备份文件，但 manifest 里没有对应条目。
  /// 成因是 softDelete 先写备份、后写 manifest，两步之间崩溃/被杀。
  /// 不清理的话，用户以为已删除的照片会一直明文占着磁盘空间。
  /// manifest 本身残缺（_degradedTrash）时禁止执行，避免误删有效备份。
  Future<int> cleanOrphanTrashFiles() async {
    if (_degradedTrash) return 0;
    final keep = <String>{_trashManifestPath};
    for (final t in trashItems) {
      keep.add(trashFileOf(t).path);
    }
    var removed = 0;
    try {
      if (!await trashDir.exists()) return 0;
      await for (final entity in trashDir.list(recursive: false)) {
        if (entity is! File) continue;
        if (keep.contains(entity.path)) continue;
        try {
          await entity.delete();
          removed++;
        } catch (err) {
          Log.e('Store', 'remove orphan failed: ${_leaf(entity.path)}', err);
        }
      }
    } catch (err) {
      Log.e('Store', 'scan trash dir failed', err);
    }
    if (removed > 0) Log.d('Store', 'removed $removed orphan trash file(s)');
    return removed;
  }

  // ---- 报告 ----

  Future<void> _loadReports() async {
    final raw = await _readJsonList(_reportsPath);
    if (raw == null) return;
    final parsed = <CleanReport>[];
    var skipped = 0;
    for (final e in raw) {
      try {
        parsed.add(CleanReport.fromJson(e));
      } catch (err) {
        skipped++;
        if (skipped <= 3) Log.e('Store', 'bad report record skipped', err);
      }
    }
    reports
      ..clear()
      ..addAll(parsed);
    if (skipped > 0) {
      _degradedReports = true;
      Log.e('Store',
          'reports.json degraded: $skipped/${raw.length} bad records, write-back disabled');
    }
  }

  Future<void> saveReports() async {
    if (_degradedReports) {
      Log.e('Store', 'reports.json degraded, refuse overwrite');
      return;
    }
    await _atomicWriteString(
      _reportsPath,
      jsonEncode(reports.map((r) => r.toJson()).toList()),
    );
  }
}
