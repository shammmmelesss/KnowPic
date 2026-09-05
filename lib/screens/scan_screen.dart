import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/scan_progress.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import 'groups_screen.dart';

/// 扫描进度页（对应文档 9.1：绝不让用户面对空白"扫描中…"）
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(scanProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('智能扫描')),
      body: switch (progress.phase) {
        ScanPhase.reading => _PhaseView(
            icon: Icons.photo_library_outlined,
            title: '正在读取相册',
            subtitle: progress.message,
          ),
        ScanPhase.analyzing => _AnalyzeView(progress: progress),
        ScanPhase.clustering => _PhaseView(
            icon: Icons.merge_type,
            title: '正在聚类分组',
            subtitle: '按 dHash 感知哈希识别相似照片…',
          ),
        ScanPhase.saving => _PhaseView(
            icon: Icons.save_outlined,
            title: '正在保存',
            subtitle: '写入特征库与分组索引…',
          ),
        ScanPhase.done => _DoneView(progress: progress),
        ScanPhase.failed => _FailedView(),
        ScanPhase.idle => _PhaseView(
            icon: Icons.search,
            title: '准备就绪',
            subtitle: '点击"开始扫描"即可整理相册',
          ),
      },
    );
  }
}

class _PhaseView extends StatelessWidget {
  const _PhaseView({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(),
          ),
        ],
      ),
    );
  }
}

class _AnalyzeView extends StatelessWidget {
  const _AnalyzeView({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('正在提取特征',
                style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '${progress.current}/${progress.total} · 流水线：缩略图 → dHash → 128 维特征 → 美学分',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '${(progress.fraction * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  const _DoneView({required this.progress});

  final ScanProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('扫描完成', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '耗时 ${(progress.elapsedMs / 1000).toStringAsFixed(1)} 秒，分析 ${progress.current} 张照片',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const GroupsScreen()),
                );
              },
              icon: const Icon(Icons.collections),
              label: const Text('查看相似组'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.error_outline,
      title: '扫描失败',
      subtitle: '请检查相册权限后重试',
      action: FilledButton(
        onPressed: () {
          Navigator.of(context).pop();
        },
        child: const Text('返回'),
      ),
    );
  }
}
