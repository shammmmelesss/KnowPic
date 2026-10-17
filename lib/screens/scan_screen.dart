import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ios_design.dart';
import '../l10n/app_strings_delegate.dart';
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
    final l10n = context.l10n;

    return Scaffold(
      appBar: frostedAppBar(context, title: l10n.scanTitle),
      body: switch (progress.phase) {
        ScanPhase.reading => _PhaseView(
            icon: CupertinoIcons.photo_on_rectangle,
            title: l10n.scanStatus(ScanPhase.reading),
            subtitle: l10n.scanStatus(
              progress.phase,
              current: progress.current,
              total: progress.total,
            ),
          ),
        ScanPhase.analyzing => _AnalyzeView(progress: progress),
        ScanPhase.clustering => _PhaseView(
            icon: CupertinoIcons.square_grid_2x2,
            title: l10n.scanStatus(ScanPhase.clustering),
            subtitle: l10n.scanClusteringSubtitle,
          ),
        ScanPhase.saving => _PhaseView(
            icon: CupertinoIcons.floppy_disk,
            title: l10n.scanStatus(ScanPhase.saving),
            subtitle: l10n.scanSavingSubtitle,
          ),
        ScanPhase.done => _DoneView(progress: progress),
        ScanPhase.failed => const _FailedView(),
        ScanPhase.idle => _PhaseView(
            icon: CupertinoIcons.search,
            title: l10n.scanStatus(ScanPhase.idle),
            subtitle: l10n.scanIdleSubtitle,
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
            Text(context.l10n.analyzeTitle,
                style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              context.l10n
                  .analyzePipeline(progress.current, progress.total),
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
            Text(context.l10n.scanStatus(ScanPhase.done),
                style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              context.l10n.scanDoneSummary(
                  progress.elapsedMs / 1000, progress.current),
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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.photo_on_rectangle, size: 18),
                  const SizedBox(width: 8),
                  Text(context.l10n.viewGroups),
                ],
              ),
            ),
            const SizedBox(height: 4),
            CupertinoButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.l10n.backHome),
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
      title: context.l10n.scanFailedTitle,
      // 不再一律归因于权限：失败原因可能是读取、写入或解析被中断
      subtitle: context.l10n.scanFailedSubtitle,
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton.filled(
            minimumSize: const Size(160, 44),
            onPressed: () => ref
                .read(scanProgressProvider.notifier)
                .startScan(incremental: false),
            child: Text(context.l10n.retry),
          ),
          const SizedBox(height: 4),
          CupertinoButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.backHome),
          ),
        ],
      ),
    );
  }
}
