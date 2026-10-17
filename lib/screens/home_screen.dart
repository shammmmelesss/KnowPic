import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ios_design.dart';
import '../l10n/app_strings_delegate.dart';
import '../models/photo_asset.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/ios_ui.dart';
import '../widgets/photo_thumb.dart';
import '../widgets/section_header.dart';
import 'groups_screen.dart';
import 'memories_screen.dart';
import 'photo_viewer_screen.dart';
import 'report_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'trash_screen.dart';

/// 首页（对应文档 9.1 首次启动引导：3 秒内看到最近照片）
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final permission = ref.watch(permissionControllerProvider);
    final progress = ref.watch(scanProgressProvider);
    final groups = ref.watch(groupsControllerProvider);
    final trash = ref.watch(trashControllerProvider);
    final assets = ref.watch(assetsControllerProvider);
    final settings = ref.watch(settingsProvider);

    final similarity = ref.watch(similarityProvider);
    final reclaimable = groups.fold<int>(
      0,
      (sum, g) => sum + similarity.estimateReclaimable(g, assets),
    );

    return Scaffold(
      body: Stack(
        children: [
          if (!permission)
            _PermissionCard(
              onGrant: () => _requestPermission(context, ref),
              onOpenSettings: () =>
                  ref.read(libraryProvider).openSystemSettings(),
            )
          else ...[
            CustomScrollView(
              slivers: [
                // 大标题直接落在页面背景上，不再套毛玻璃栏，视觉更轻
                SliverToBoxAdapter(
                  child: _HomeHeader(
                    greeting: l10n.greeting(DateTime.now()),
                    onSettings: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ),
                CupertinoSliverRefreshControl(
                  onRefresh: () async {
                    ref.invalidate(recentPhotosProvider);
                    ref.read(groupsControllerProvider.notifier).reload();
                    ref.read(trashControllerProvider.notifier).reload();
                  },
                ),
                SliverToBoxAdapter(
                  child: _StatsCard(
                    scannedCount: assets.length,
                    groupCount: groups.length,
                    reclaimableBytes: reclaimable,
                    lastScanAt: settings.lastScanAt,
                    scanning: progress.isRunning,
                    onRescan: () => _startScan(context, ref),
                  ),
                ),
                SliverToBoxAdapter(
                    child: SectionHeader(title: l10n.quickEntries)),
                SliverToBoxAdapter(
                  child: _QuickActions(
                    groupCount: groups.length,
                    trashCount: trash.length,
                    onGroups: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const GroupsScreen()),
                    ),
                    onTrash: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TrashScreen()),
                    ),
                    onReport: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ReportScreen()),
                    ),
                    onMemories: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const MemoriesScreen()),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                    child: SectionHeader(title: l10n.recent30Days)),
                ..._recentSlivers(context, ref),
              ],
            ),
            // 底部整宽主行动，替代原先悬浮在右下角的胶囊
            _BottomScanBar(
              running: progress.isRunning,
              onTap: () => _startScan(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _requestPermission(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(permissionControllerProvider.notifier).request();
    // iOS 上拒绝过一次后系统不再弹窗，requestPermission 只会立刻返回失败。
    // 必须给出可见反馈 + 手动开启的出路，否则用户点了「授权」页面毫无变化。
    if (!ok && context.mounted) {
      showIosToast(context, context.l10n.permissionToast);
    }
  }

  void _openViewer(BuildContext context, List<PhotoAsset> photos, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(assets: photos, initialIndex: index),
      ),
    );
  }

  void _startScan(BuildContext context, WidgetRef ref) {
    final progress = ref.read(scanProgressProvider);
    if (progress.isRunning) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    // 启动后台扫描（文档 9.1：立即见内容，后台整理）
    ref.read(scanProgressProvider.notifier).startScan(incremental: true);
  }

  List<Widget> _recentSlivers(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentPhotosProvider);
    return recent.when(
      loading: () => const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CupertinoActivityIndicator()),
          ),
        ),
      ],
      error: (e, _) => [
        SliverToBoxAdapter(
          child: EmptyState(
            icon: CupertinoIcons.exclamationmark_circle,
            title: context.l10n.readLibraryFailed,
            subtitle: '$e',
          ),
        ),
      ],
      data: (photos) {
        if (photos.isEmpty) {
          // 空态在剩余空间内垂直居中，而不是贴着标题
          return const [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: _RecentEmptyState()),
            ),
          ];
        }
        final indexById = {
          for (var i = 0; i < photos.length; i++) photos[i].id: i,
        };
        return [
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 140),
            sliver: SliverGrid(
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 1,
                mainAxisSpacing: 1,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => GestureDetector(
                  key: ValueKey(photos[i].id),
                  onTap: () => _openViewer(context, photos, i),
                  child: PhotoThumb(assetId: photos[i].id),
                ),
                childCount: photos.length,
                // Element 跟着资产 id 走而非跟着位置走：
                // 按位置复用 State 会让格子显示成上一张照片
                findChildIndexCallback: (key) =>
                    indexById[(key as ValueKey<String>).value],
              ),
            ),
          ),
        ];
      },
    );
  }
}

/// 页面头部：问候语 + 大标题 + 设置入口
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.greeting, required this.onSettings});

  final String greeting;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 10,
        16,
        18,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Ios.secondaryLabel(b),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.appTitle,
                  style: theme.textTheme.displayLarge?.copyWith(
                    fontSize: 34,
                    letterSpacing: -0.6,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Semantics(
              button: true,
              label: context.l10n.settings,
              child: SizedBox(
                width: 44,
                height: 44,
                child: IosPressable(
                  onTap: onSettings,
                  scale: 0.92,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Ios.fill(b),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.gear_alt,
                        size: 19,
                        color: Ios.secondaryLabel(b),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 相册空间概览：品牌渐变卡片，承载三个核心数字
class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.scannedCount,
    required this.groupCount,
    required this.reclaimableBytes,
    this.lastScanAt,
    this.onRescan,
    this.scanning = false,
  });

  final int scannedCount;
  final int groupCount;
  final int reclaimableBytes;
  final DateTime? lastScanAt;
  final VoidCallback? onRescan;
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bytes = Ios.formatBytes(reclaimableBytes).split(' ');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4B6BFB), Color(0xFF7B5BF7)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4B6BFB).withValues(alpha: 0.26),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // 右上角柔光，避免大面积纯色发闷
            Positioned(
              right: -50,
              top: -70,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.statsTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 44,
                        child: Center(
                          child: _RescanPill(
                            scanning: scanning,
                            onTap: scanning ? null : onRescan,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _StatItem(
                        icon: CupertinoIcons.photo_on_rectangle,
                        value: '$scannedCount',
                        unit: l10n.photoUnit,
                        label: l10n.statScanned,
                      ),
                      _StatItem(
                        icon: CupertinoIcons.collections,
                        value: '$groupCount',
                        unit: l10n.groupUnit,
                        label: l10n.statGroups,
                      ),
                      _StatItem(
                        icon: CupertinoIcons.arrow_down_circle,
                        value: bytes.first,
                        unit: bytes.length > 1 ? bytes[1] : '',
                        label: l10n.statReclaimable,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 0.5,
                    color: Colors.white.withValues(alpha: 0.22),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        CupertinoIcons.clock,
                        size: 13,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          lastScanAt == null
                              ? l10n.noScanRecord
                              : '${l10n.lastScanPrefix}'
                                  '${l10n.formatMonthDayTime(lastScanAt!)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RescanPill extends StatelessWidget {
  const _RescanPill({required this.scanning, this.onTap});

  final bool scanning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IosPressable(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          scanning ? context.l10n.scanning : context.l10n.rescan,
          style: TextStyle(
            color: Colors.white.withValues(alpha: scanning ? 0.7 : 1),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 12,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.groupCount,
    required this.trashCount,
    required this.onGroups,
    required this.onTrash,
    required this.onReport,
    required this.onMemories,
  });

  final int groupCount;
  final int trashCount;
  final VoidCallback onGroups;
  final VoidCallback onTrash;
  final VoidCallback onReport;
  final VoidCallback onMemories;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _QuickAction(
              id: 'groups',
              icon: CupertinoIcons.photo_on_rectangle,
              label: l10n.quickGroups,
              tint: Ios.blue(b),
              badge: groupCount,
              onTap: onGroups),
          _QuickAction(
              id: 'trash',
              icon: CupertinoIcons.trash,
              label: l10n.quickTrash,
              tint: Ios.orange(b),
              badge: trashCount,
              onTap: onTrash),
          _QuickAction(
              id: 'report',
              icon: CupertinoIcons.chart_bar,
              label: l10n.quickReport,
              tint: Ios.green(b),
              onTap: onReport),
          _QuickAction(
              id: 'memories',
              icon: CupertinoIcons.sparkles,
              label: l10n.quickMemories,
              tint: Ios.purple(b),
              onTap: onMemories),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.tint,
    this.badge = 0,
    required this.onTap,
  });

  /// 稳定标识：Widget key 不能跟着语言变，否则换语言后测试/自动化找不到入口
  final String id;
  final IconData icon;
  final String label;
  final Color tint;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return Expanded(
      child: IosPressable(
        key: ValueKey('qa_$id'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.13),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, size: 24, color: tint),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -5,
                      top: -5,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: Ios.red(b),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Ios.bg(b), width: 1.5),
                        ),
                        child: Center(
                          child: Text(
                            '$badge',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              height: 1.1,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Ios.label(b),
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 最近照片为空：圆形图标底 + 单行说明，视觉重心更稳
class _RecentEmptyState extends StatelessWidget {
  const _RecentEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 108,
            height: 108,
            child: Stack(
              children: [
                Container(
                  width: 108,
                  height: 108,
                  decoration: BoxDecoration(
                    color: Ios.fill(b),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.photo,
                    size: 44,
                    color: Ios.secondaryLabel(b),
                  ),
                ),
                Positioned(
                  right: 24,
                  bottom: 28,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: Ios.card(b),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.plus,
                      size: 15,
                      color: Ios.blue(b),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            context.l10n.recentEmptyTitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ],
      ),
    );
  }
}

/// 底部主行动：渐变遮罩 + 整宽蓝色胶囊
class _BottomScanBar extends StatelessWidget {
  const _BottomScanBar({required this.running, required this.onTap});

  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final bg = Ios.bg(b);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IgnorePointer(
            child: Container(
              height: 28,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [bg.withValues(alpha: 0), bg],
                ),
              ),
            ),
          ),
          Container(
            color: bg,
            padding: EdgeInsets.fromLTRB(20, 0, 20, bottomInset + 12),
            child: IosPressable(
              onTap: running ? null : onTap,
              scale: 0.97,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  color: Ios.blue(b).withValues(alpha: running ? 0.6 : 1),
                  borderRadius: BorderRadius.circular(27),
                  boxShadow: [
                    BoxShadow(
                      color: Ios.blue(b).withValues(alpha: 0.28),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      running
                          ? CupertinoIcons.hourglass
                          : CupertinoIcons.search,
                      size: 20,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      running ? context.l10n.scanning : context.l10n.startScan,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.41,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onGrant, required this.onOpenSettings});

  final VoidCallback onGrant;

  /// 系统已不再弹窗时（用户拒绝过一次）的唯一出路
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final l10n = context.l10n;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.photo_on_rectangle,
                size: 72, color: Ios.blue(b)),
            const SizedBox(height: 20),
            Text(
              l10n.permissionTitle,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            IosCard(
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    TextSpan(text: l10n.permissionBodyLead),
                    TextSpan(
                        text: l10n.permissionBodyStrong,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    TextSpan(text: l10n.permissionBodyTail),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.permissionNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Ios.tertiaryLabel(b)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: onGrant,
              child: Text(l10n.grantAccess),
            ),
            const SizedBox(height: 4),
            CupertinoButton(
              onPressed: onOpenSettings,
              child: Text(
                l10n.openSystemSettings,
                style: TextStyle(color: Ios.blue(b), fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
