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
      Log.e('Store', 'read json failed: $path', err);
      return null;
    }
  }

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
    try {
      for (final e in raw) {
        final a = PhotoAsset.fromJson(e);
        assets[a.id] = a;
      }
      await _loadFeatures();
    } catch (err) {
      Log.e('Store', 'load assets failed', err);
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
    await saveAssets();
    await saveGroups();
  }

  Float32List? assetFeatures(String id) => assets[id]?.features;

  // ---- 分组 ----

  Future<void> _loadGroups() async {
    final raw = await _readJsonList(_groupsPath);
    if (raw == null) return;
    try {
      groups.addAll(raw.map(SimilarGroup.fromJson));
    } catch (err) {
      Log.e('Store', 'load groups failed', err);
    }
  }

  Future<void> saveGroups() async {
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
    try {
      trashItems.addAll(raw.map(TrashItem.fromJson));
    } catch (err) {
      Log.e('Store', 'load trash failed', err);
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
    var name = item.savedFileName
        .replaceAll('/', '')
        .replaceAll(r'\', '')
        .replaceAll('..', '');
    if (name.isEmpty || name == '.' ) name = 'orphan.bin';
    return File('${trashDir.path}/$name');
  }

  // ---- 报告 ----

  Future<void> _loadReports() async {
    final raw = await _readJsonList(_reportsPath);
    if (raw == null) return;
    try {
      reports.addAll(raw.map(CleanReport.fromJson));
    } catch (err) {
      Log.e('Store', 'load reports failed', err);
    }
  }

  Future<void> saveReports() async {
    await _atomicWriteString(
      _reportsPath,
      jsonEncode(reports.map((r) => r.toJson()).toList()),
    );
  }
}
