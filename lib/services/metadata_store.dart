import 'dart:convert';
import 'dart:io';
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
  late PreferenceModel preference;

  String get _assetsPath => '${metaDir.path}/${AppConfig.assetsFile}';
  String get _featuresPath => '${metaDir.path}/${AppConfig.featuresFile}';
  String get _groupsPath => '${metaDir.path}/${AppConfig.groupsFile}';
  String get _prefPath => '${metaDir.path}/${AppConfig.userPrefFile}';
  String get _trashManifestPath => '${trashDir.path}/${AppConfig.trashManifestFile}';
  String get _reportsPath => '${metaDir.path}/${AppConfig.reportsFile}';

  /// 偏好模型文件（导出用）
  File get prefFile => File(_prefPath);

  /// 初始化目录并加载所有持久化数据
  Future<void> init() async {
    if (!await metaDir.exists()) await metaDir.create(recursive: true);
    if (!await trashDir.exists()) await trashDir.create(recursive: true);
    preference = PreferenceModel();
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
    final f = File(_assetsPath);
    if (!await f.exists()) return;
    try {
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      for (final e in list) {
        final a = PhotoAsset.fromJson(e as Map<String, dynamic>);
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
    final count = data.length ~/ (dim * 4);
    if (count == 0) return;
    final sortedIds = assets.keys.toList()..sort();
    for (int i = 0; i < count && i < sortedIds.length; i++) {
      final slice = Float32List.sublistView(
          data, i * dim * 4, (i + 1) * dim * 4);
      assets[sortedIds[i]]!.features = slice;
    }
  }

  /// 全量保存资产 + 特征（简单可靠的全量重写）
  Future<void> saveAssets() async {
    final sorted = assets.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    await File(_assetsPath).writeAsString(
      jsonEncode(sorted.map((a) => a.toJson()).toList()),
      flush: true,
    );
    // 特征二进制：float32 小端
    final total = sorted.length * AppConfig.featureDim;
    if (total == 0) {
      await File(_featuresPath).writeAsBytes(const []);
      return;
    }
    final bytes = ByteData(total * 4);
    var offset = 0;
    for (final a in sorted) {
      for (final v in a.features) {
        bytes.setFloat32(offset, v, Endian.little);
        offset += 4;
      }
    }
    await File(_featuresPath).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

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
    final f = File(_groupsPath);
    if (!await f.exists()) return;
    try {
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      groups.addAll(list.map((e) => SimilarGroup.fromJson(e as Map<String, dynamic>)));
    } catch (err) {
      Log.e('Store', 'load groups failed', err);
    }
  }

  Future<void> saveGroups() async {
    await File(_groupsPath).writeAsString(
      jsonEncode(groups.map((g) => g.toJson()).toList()),
      flush: true,
    );
  }

  // ---- 偏好 ----

  Future<void> _loadPref() async {
    final f = File(_prefPath);
    if (!await f.exists()) return;
    try {
      final json = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      preference = PreferenceModel.fromJson(json);
    } catch (err) {
      Log.e('Store', 'load pref failed', err);
    }
  }

  Future<void> savePref() async {
    await File(_prefPath).writeAsString(
      jsonEncode(preference.toJson()),
      flush: true,
    );
  }

  // ---- 回收站 ----

  Future<void> _loadTrash() async {
    final f = File(_trashManifestPath);
    if (!await f.exists()) return;
    try {
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      trashItems.addAll(list.map((e) => TrashItem.fromJson(e as Map<String, dynamic>)));
    } catch (err) {
      Log.e('Store', 'load trash failed', err);
    }
  }

  Future<void> saveTrash() async {
    await File(_trashManifestPath).writeAsString(
      jsonEncode(trashItems.map((t) => t.toJson()).toList()),
      flush: true,
    );
  }

  File trashFileOf(TrashItem item) => File('${trashDir.path}/${item.savedFileName}');

  // ---- 报告 ----

  Future<void> _loadReports() async {
    final f = File(_reportsPath);
    if (!await f.exists()) return;
    try {
      final list = jsonDecode(await f.readAsString()) as List<dynamic>;
      reports.addAll(list.map((e) => CleanReport.fromJson(e as Map<String, dynamic>)));
    } catch (err) {
      Log.e('Store', 'load reports failed', err);
    }
  }

  Future<void> saveReports() async {
    await File(_reportsPath).writeAsString(
      jsonEncode(reports.map((r) => r.toJson()).toList()),
      flush: true,
    );
  }
}
