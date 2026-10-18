import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logger.dart';
import '../l10n/app_strings.dart';
import '../models/photo_asset.dart';
import '../models/scan_progress.dart';
import '../models/scan_report.dart';
import '../models/similar_group.dart';
import '../models/trash_item.dart';
import '../services/app_settings.dart';
import '../services/learning_service.dart';
import '../services/metadata_store.dart';
import '../services/photo_library_service.dart';
import '../services/ranking_service.dart';
import '../services/report_service.dart';
import '../services/scanner_service.dart';
import '../services/secure_key_service.dart';
import '../services/similarity_service.dart';
import '../services/trash_service.dart';

// ---- 服务注入（main() 中 override 带依赖的服务）----

final storeProvider = Provider<MetadataStore>(
  (ref) => throw UnimplementedError('MetadataStore 需在 main 中注入'),
);

/// 偏好导出/导入用的密钥（iOS 走钥匙串，见 SecureKeyService）
final secureKeyProvider = Provider<SecureKeyService>(
  (ref) => SecureKeyService(ref.watch(storeProvider).rootDir),
);

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends Notifier<AppSettings> {
  AppSettings? _initial;

  /// 由 main() 注入初始值
  set initial(AppSettings v) => _initial = v;

  @override
  AppSettings build() => _initial ??
      (throw UnimplementedError('SettingsController 需在 main 中 override'));

  Future<void> toggleHelpImprove(bool v) async {
    state = state.copyWith(helpImprove: v);
    await state.save(ref.read(storeProvider).rootDir);
  }

  Future<void> toggleConfirmBeforeDelete(bool v) async {
    state = state.copyWith(confirmBeforeDelete: v);
    await state.save(ref.read(storeProvider).rootDir);
  }

  Future<void> setLanguageMode(String mode) async {
    state = state.copyWith(languageMode: mode);
    await state.save(ref.read(storeProvider).rootDir);
  }

  Future<void> updateLastScan() async {
    state = state.copyWith(lastScanAt: DateTime.now());
    await state.save(ref.read(storeProvider).rootDir);
  }
}

/// 界面语言：设置里选了具体语言就用它，否则跟随系统（不支持的系统语言回落中文）
final localeProvider = Provider<Locale>((ref) {
  final mode = ref.watch(settingsProvider).languageMode;
  final picked = AppLanguage.fromCode(mode).locale;
  if (picked != null) return picked;
  return AppStrings.resolveSystem(
      WidgetsBinding.instance.platformDispatcher.locale);
});

final libraryProvider = Provider<PhotoLibraryService>(
  (ref) => PhotoManagerLibrary(),
);

final learningProvider = Provider<LearningService>(
  (ref) => LearningService(ref.watch(storeProvider)),
);

final similarityProvider = Provider<SimilarityService>(
  (ref) => SimilarityService(),
);

final rankingProvider = Provider<RankingService>(
  (ref) => RankingService(ref.watch(learningProvider)),
);

final scannerProvider = Provider<ScannerService>(
  (ref) => ScannerService(
    library: ref.watch(libraryProvider),
    store: ref.watch(storeProvider),
    similarity: ref.watch(similarityProvider),
    ranking: ref.watch(rankingProvider),
  ),
);

final trashProvider = Provider<TrashService>(
  (ref) => TrashService(ref.watch(storeProvider), ref.watch(libraryProvider)),
);

final reportProvider = Provider<ReportService>(
  (ref) => ReportService(ref.watch(storeProvider)),
);

// ---- 权限 ----

final permissionControllerProvider =
    NotifierProvider<PermissionController, bool>(PermissionController.new);

class PermissionController extends Notifier<bool> {
  @override
  bool build() {
    // 冷启动恢复真实授权状态（文档 9.1：3 秒内看到内容）。
    // 先静默检查当前授权：系统已记住授权则直接恢复，无需任何交互；
    // 未授权时：首次使用等待用户点击授权卡片（避免启动即弹系统窗），
    // 有历史数据（此前授权使用过）才主动请求恢复。
    () async {
      try {
        final lib = ref.read(libraryProvider);
        var ok = await lib.checkPermission();
        if (!ref.mounted) return;
        if (!ok) {
          final store = ref.read(storeProvider);
          if (store.assets.isEmpty) return; // 首次使用：等待用户主动授权
          ok = await lib.requestPermission();
        }
        // await 之后 provider 可能已被 dispose：先确认还活着再写 state
        if (!ref.mounted) return;
        if (ok && !state) {
          state = true;
          ref.invalidate(recentPhotosProvider);
        }
      } catch (err) {
        Log.e('Permission', 'restore permission failed', err);
      }
    }();
    return ref.watch(libraryProvider).hasPermission;
  }

  Future<bool> request() async {
    final ok = await ref.read(libraryProvider).requestPermission();
    state = ok;
    if (ok) {
      ref.invalidate(recentPhotosProvider);
    }
    return ok;
  }

  /// 回前台时重新核对权限：用户可能刚在系统设置里改过授权，
  /// 不做这一步界面会一直停在「未授权」，用户以为设置没生效。
  Future<void> recheck() async {
    try {
      final ok = await ref.read(libraryProvider).checkPermission();
      if (!ref.mounted || ok == state) return;
      state = ok;
      if (ok) ref.invalidate(recentPhotosProvider);
    } catch (err) {
      Log.e('Permission', 'recheck failed', err);
    }
  }
}

/// 最近 30 天照片（首页冷启动展示，文档 9.1）
final recentPhotosProvider = FutureProvider<List<PhotoAsset>>((ref) async {
  final lib = ref.watch(libraryProvider);
  final cutoff = DateTime.now().subtract(const Duration(days: 30));
  // 传入时间下界：服务端按倒序分页早停，避免为首页卡片探测整个相册
  final photos = await lib.loadAllPhotos(newerThan: cutoff);
  final recent =
      photos.where((p) => p.createdTime.isAfter(cutoff)).toList()
        ..sort((a, b) => b.createdTime.compareTo(a.createdTime));
  return recent;
});

// ---- 扫描 ----

final scanProgressProvider =
    NotifierProvider<ScanProgressController, ScanProgress>(ScanProgressController.new);

class ScanProgressController extends Notifier<ScanProgress> {
  VoidCallback? _listener;
  ValueNotifier<ScanProgress>? _progress;

  @override
  ScanProgress build() {
    final progress = ref.read(scannerProvider).progress;
    if (_listener != null && _progress != null) {
      _progress!.removeListener(_listener!);
    }
    _progress = progress;
    _listener = () {
      final p = progress.value;
      state = p;
      if (p.phase == ScanPhase.done) {
        // 扫描完成 → 刷新分组/资产视图
        ref.read(groupsControllerProvider.notifier).reload();
        ref.read(assetsControllerProvider.notifier).reload();
      }
    };
    progress.addListener(_listener!);
    ref.onDispose(() {
      if (_listener != null) progress.removeListener(_listener!);
    });
    return progress.value;
  }

  Future<bool> startScan({bool incremental = false}) async {
    final scanner = ref.read(scannerProvider);
    try {
      if (incremental) {
        await scanner.incrementalScan();
      } else {
        await scanner.fullScan();
      }
      await ref.read(settingsProvider.notifier).updateLastScan();
      return true;
    } on ScanCanceledException {
      return false;
    } catch (err) {
      // 静默吞掉会让「扫描失败」无从诊断，至少落到日志
      Log.e('Scan', 'startScan failed', err);
      return false;
    }
  }

  /// 取消进行中的扫描
  void cancelScan() => ref.read(scannerProvider).cancel();

  bool get isBusy => state.isRunning || ref.read(scannerProvider).isRunning;
}

// ---- 资产与分组 ----

final assetsControllerProvider =
    NotifierProvider<AssetsController, Map<String, PhotoAsset>>(AssetsController.new);

class AssetsController extends Notifier<Map<String, PhotoAsset>> {
  @override
  Map<String, PhotoAsset> build() {
    ref.keepAlive();
    return Map.of(ref.watch(storeProvider).assets);
  }

  void reload() => state = Map.of(ref.read(storeProvider).assets);
}

final groupsControllerProvider =
    NotifierProvider<GroupsController, List<SimilarGroup>>(GroupsController.new);

class GroupsController extends Notifier<List<SimilarGroup>> {
  @override
  List<SimilarGroup> build() {
    ref.keepAlive();
    return List.of(ref.watch(storeProvider).groups);
  }

  void reload() => state = List.of(ref.read(storeProvider).groups);
}

// ---- 回收站 ----

final trashControllerProvider =
    NotifierProvider<TrashController, List<TrashItem>>(TrashController.new);

class TrashController extends Notifier<List<TrashItem>> {
  @override
  List<TrashItem> build() {
    ref.keepAlive();
    return List.of(ref.watch(storeProvider).trashItems);
  }

  void reload() => state = List.of(ref.read(storeProvider).trashItems);
}

// ---- 清理报告 ----

final reportsControllerProvider =
    NotifierProvider<ReportsController, List<CleanReport>>(ReportsController.new);

class ReportsController extends Notifier<List<CleanReport>> {
  @override
  List<CleanReport> build() {
    ref.keepAlive();
    return List.of(ref.watch(storeProvider).reports);
  }

  void reload() => state = List.of(ref.read(storeProvider).reports);
}
