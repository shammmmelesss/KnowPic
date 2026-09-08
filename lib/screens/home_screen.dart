import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ios_design.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/ios_ui.dart';
import '../widgets/photo_thumb.dart';
import '../widgets/section_header.dart';
import 'groups_screen.dart';
import 'memories_screen.dart';
import 'report_screen.dart';
import 'scan_screen.dart';
import 'settings_screen.dart';
import 'trash_screen.dart';

/// 首页（对应文档 9.1 首次启动引导：3 秒内看到最近照片）
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                onGrant: () =>
                    ref.read(permissionControllerProvider.notifier).request())
          else ...[
            CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  title: const Text('KnowPic'),
                  backgroundColor: Colors.transparent,
                  flexibleSpace: frostedBar(context),
                  actions: [
                    IconButton(
                      icon: const Icon(CupertinoIcons.gear_alt),
                      tooltip: '设置',
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const SettingsScreen()),
                      ),
                    ),
                  ],
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
                  ),
                ),
                const SliverToBoxAdapter(
                    child: SectionHeader(title: '快捷入口')),
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
                const SliverToBoxAdapter(
                    child: SectionHeader(title: '最近 30 天')),
                ..._recentSlivers(context, ref),
              ],
            ),
            Positioned(
              right: 20,
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              child: _ScanCapsule(
                running: progress.isRunning,
                onTap: () => _startScan(context, ref),
              ),
            ),
          ],
        ],
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
            title: '读取相册失败',
            subtitle: '$e',
          ),
        ),
      ],
      data: (photos) {
        if (photos.isEmpty) {
          return const [
            SliverToBoxAdapter(
              child: EmptyState(
                icon: CupertinoIcons.photo_on_rectangle,
                title: '最近 30 天暂无照片',
                subtitle: '点击右下角「开始扫描」，在后台整理全部照片',
              ),
            ),
          ];
        }
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
                (context, i) => PhotoThumb(assetId: photos[i].id),
                childCount: photos.length,
              ),
            ),
          ),
        ];
      },
    );
  }
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.scannedCount,
    required this.groupCount,
    required this.reclaimableBytes,
    this.lastScanAt,
  });

  final int scannedCount;
  final int groupCount;
  final int reclaimableBytes;
  final DateTime? lastScanAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return IosCard(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('相册空间概览', style: theme.textTheme.titleMedium),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatItem(
                  icon: CupertinoIcons.photo_on_rectangle,
                  label: '已扫描',
                  value: '$scannedCount 张'),
              _StatItem(
                  icon: CupertinoIcons.collections,
                  label: '相似组',
                  value: '$groupCount 组'),
              _StatItem(
                  icon: CupertinoIcons.arrow_down_circle,
                  label: '可释放',
                  value: Ios.formatBytes(reclaimableBytes)),
            ],
          ),
          if (lastScanAt != null) ...[
            const SizedBox(height: 10),
            Text(
              '上次扫描：${lastScanAt!.month}月${lastScanAt!.day}日 ${lastScanAt!.hour.toString().padLeft(2, '0')}:${lastScanAt!.minute.toString().padLeft(2, '0')}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Ios.tertiaryLabel(b)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: Ios.blue(b)),
          const SizedBox(height: 6),
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _QuickAction(
              icon: CupertinoIcons.photo_on_rectangle,
              label: '相似组',
              tint: Ios.blue(b),
              badge: groupCount,
              onTap: onGroups),
          _QuickAction(
              icon: CupertinoIcons.trash,
              label: '回收站',
              tint: Ios.orange(b),
              badge: trashCount,
              onTap: onTrash),
          _QuickAction(
              icon: CupertinoIcons.chart_bar,
              label: '清理报告',
              tint: Ios.green(b),
              onTap: onReport),
          _QuickAction(
              icon: CupertinoIcons.sparkles,
              label: '记忆',
              tint: Ios.purple(b),
              onTap: onMemories),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.tint,
    this.badge = 0,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Expanded(
      child: IosPressable(
        key: ValueKey('qa_$label'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tint.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 22, color: tint),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -4,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Ios.red(b),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badge',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// 毛玻璃悬浮胶囊主按钮（对应 iOS 悬浮主操作）
class _ScanCapsule extends StatelessWidget {
  const _ScanCapsule({required this.running, required this.onTap});

  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    return IosPressable(
      onTap: onTap,
      scale: 0.95,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Ios.blue(b).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Ios.blue(b).withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  running ? CupertinoIcons.hourglass : CupertinoIcons.search,
                  size: 20,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  running ? '扫描中…' : '开始扫描',
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
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
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
              '整理重复照片，需要一个相册权限',
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            IosCard(
              child: Text.rich(
                TextSpan(
                  style: theme.textTheme.bodyMedium,
                  children: [
                    const TextSpan(
                        text: '为了帮您找到重复照片，我们需要读取相册。\n所有分析均在手机本地完成，'),
                    TextSpan(
                        text: '绝不联网上传',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const TextSpan(text: '。'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '您可以选择「部分照片」授权，App 会优雅降级；\n图片也不会离开您的设备。',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Ios.tertiaryLabel(b)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: onGrant,
              child: const Text('授权访问相册'),
            ),
          ],
        ),
      ),
    );
  }
}
