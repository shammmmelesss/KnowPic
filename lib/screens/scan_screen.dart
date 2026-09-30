import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ios_design.dart';
import '../models/scan_progress.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/ios_ui.dart';
import 'groups_screen.dart';

/// 扫描进度页（对应文档 9.1：绝不让用户面对空白"扫描中…"）
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(scanProgressProvider);

    return Scaffold(
      appBar: frostedAppBar(context, title: '智能扫描'),
      body: switch (progress.phase) {
        ScanPhase.reading => _PhaseView(
            icon: CupertinoIcons.photo_on_rectangle,
            title: '正在读取相册',
            subtitle: progress.message,
          ),
        ScanPhase.analyzing => _AnalyzeView(progress: progress),
        ScanPhase.clustering => _PhaseView(
            icon: CupertinoIcons.square_grid_2x2,
            title: '正在聚类分组',
            subtitle: '按 dHash 感知哈希识别相似照片…',
          ),
        ScanPhase.saving => _PhaseView(
            icon: CupertinoIcons.floppy_disk,
            title: '正在保存',
            subtitle: '写入特征库与分组索引…',
          ),
        ScanPhase.done => _DoneView(progress: progress),
        ScanPhase.failed => const _FailedView(),
        ScanPhase.idle => _PhaseView(
            icon: CupertinoIcons.search,
            title: '准备就绪',
            subtitle: '点击「开始扫描」即可整理相册',
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
    final b = theme.brightness;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: Ios.blue(b)),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Ios.secondaryLabel(b)),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),
          const CupertinoActivityIndicator(radius: 16),
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
    final b = theme.brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('正在提取特征', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '${progress.current}/${progress.total} · 流水线：缩略图 → dHash → 128 维特征 → 美学分',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.fraction,
                minHeight: 8,
                backgroundColor: Ios.fill(b),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '${(progress.fraction * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.displayLarge,
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
    final b = theme.brightness;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.check_mark_circled,
                size: 64, color: Ios.green(b)),
            const SizedBox(height: 16),
            Text('扫描完成', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              '耗时 ${(progress.elapsedMs / 1000).toStringAsFixed(1)} 秒，分析 ${progress.current} 张照片',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Ios.secondaryLabel(b)),
            ),
            const SizedBox(height: 28),
            CupertinoButton.filled(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const GroupsScreen()),
                );
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.photo_on_rectangle, size: 18),
                  SizedBox(width: 8),
                  Text('查看相似组'),
                ],
              ),
            ),
            const SizedBox(height: 4),
            CupertinoButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FailedView extends ConsumerWidget {
  const _FailedView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EmptyState(
      icon: CupertinoIcons.exclamationmark_circle,
      title: '扫描未能完成',
      // 不再一律归因于权限：失败原因可能是读取、写入或解析被中断
      subtitle: '扫描过程中断，可重试或返回首页稍后再试',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton.filled(
            minimumSize: const Size(160, 44),
            onPressed: () => ref
                .read(scanProgressProvider.notifier)
                .startScan(incremental: false),
            child: const Text('重试'),
          ),
          const SizedBox(height: 4),
          CupertinoButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回首页'),
          ),
        ],
      ),
    );
  }
}
