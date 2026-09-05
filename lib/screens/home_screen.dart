import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_progress.dart';
import '../providers/providers.dart';
import '../services/app_settings.dart';
import '../widgets/empty_state.dart';
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
      appBar: AppBar(
        title: const Text('KnowPic 智能相册整理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: permission
          ? FloatingActionButton.extended(
              onPressed: () => _startScan(context, ref),
              icon: Icon(progress.isRunning ? Icons.hourglass_top : Icons.search),
              label: Text(progress.isRunning ? '扫描中…' : '开始扫描'),
            )
          : null,
      body: permission
          ? _buildBody(context, ref, progress, groups, trash, settings, reclaimable)
          : _PermissionCard(onGrant: () => ref.read(permissionControllerProvider.notifier).request()),
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

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ScanProgress progress,
    List groups,
    List trash,
    AppSettings settings,
    int reclaimable,
  ) {
    final store = ref.watch(storeProvider);
    final scannedCount = store.assets.length;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(recentPhotosProvider);
        ref.read(groupsControllerProvider.notifier).reload();
        ref.read(trashControllerProvider.notifier).reload();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _StatsCard(
            scannedCount: scannedCount,
            groupCount: groups.length,
            reclaimableBytes: reclaimable,
            lastScanAt: settings.lastScanAt,
          ),
          const SectionHeader(title: '快捷入口'),
          _QuickActions(
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
              MaterialPageRoute(builder: (_) => const MemoriesScreen()),
            ),
          ),
          const SectionHeader(title: '最近 30 天'),
          const _RecentGrid(),
        ],
      ),
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

  String _fmt(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('相册空间概览', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                _StatItem(label: '已扫描', value: '$scannedCount 张', icon: Icons.photo_library),
                _StatItem(label: '相似组', value: '$groupCount 组', icon: Icons.collections),
                _StatItem(
                  label: '可释放',
                  value: _fmt(reclaimableBytes),
                  icon: Icons.sd_storage_outlined,
                ),
              ],
            ),
            if (lastScanAt != null) ...[
              const SizedBox(height: 8),
              Text(
                '上次扫描：${lastScanAt!.month}月${lastScanAt!.day}日 ${lastScanAt!.hour.toString().padLeft(2, '0')}:${lastScanAt!.minute.toString().padLeft(2, '0')}',
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
          ],
        ),
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
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 22, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(value,
              style: theme.textTheme.titleSmall
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _QuickAction(
            icon: Icons.collections,
            label: '相似组',
            badge: groupCount,
            onTap: onGroups,
          ),
          _QuickAction(
            icon: Icons.delete_outline,
            label: '回收站',
            badge: trashCount,
            onTap: onTrash,
          ),
          _QuickAction(
            icon: Icons.bar_chart,
            label: '清理报告',
            onTap: onReport,
          ),
          _QuickAction(
            icon: Icons.auto_awesome,
            label: '记忆',
            onTap: onMemories,
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    this.badge = 0,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(icon,
                        size: 22, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  if (badge > 0)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.error,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$badge',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onError,
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

class _RecentGrid extends ConsumerWidget {
  const _RecentGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentPhotosProvider);
    return recent.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => EmptyState(
        icon: Icons.error_outline,
        title: '读取相册失败',
        subtitle: '$e',
      ),
      data: (photos) {
        if (photos.isEmpty) {
          return const EmptyState(
            icon: Icons.photo_library_outlined,
            title: '最近 30 天暂无照片',
            subtitle: '点击右下角"开始扫描"，在后台整理全部照片',
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 4,
            mainAxisSpacing: 4,
          ),
          itemCount: photos.length,
          itemBuilder: (context, i) {
            final p = photos[i];
            return PhotoThumb(assetId: p.id, borderRadius: BorderRadius.circular(6));
          },
        );
      },
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 72, color: cs.primary),
            const SizedBox(height: 20),
            Text(
              '整理重复照片，需要一个相册权限',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '为了帮您找到重复照片，我们需要读取相册。\n所有分析均在手机本地完成，**绝不联网上传**。',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '您可以选择"部分照片"授权，App 会优雅降级；\n图片也不会离开您的设备。',
              style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onGrant,
              icon: const Icon(Icons.check),
              label: const Text('授权访问相册'),
            ),
          ],
        ),
      ),
    );
  }
}
