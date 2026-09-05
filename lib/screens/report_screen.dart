import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/group_type.dart';
import '../models/scan_report.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';

/// 清理报告页（对应文档 9.5 清理报告 / 14 空间释放可视化）
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  bool _finalized = false;

  @override
  void initState() {
    super.initState();
    // 进入页面时把本次清理会话落库为报告
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_finalized) return;
      _finalized = true;
      await ref.read(reportProvider).finalize();
      if (mounted) {
        ref.read(reportsControllerProvider.notifier).reload();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(reportsControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('清理报告')),
      body: reports.isEmpty
          ? const EmptyState(
              icon: Icons.bar_chart,
              title: '还没有清理记录',
              subtitle: '完成一次"一键清理"后，这里会展示释放的空间',
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (var i = 0; i < reports.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _ReportCard(
                      report: reports[i],
                      highlight: i == 0,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, this.highlight = false});

  final CleanReport report;
  final bool highlight;

  static const _typeLabels = {
    GroupType.burst: '连拍',
    GroupType.editHistory: '修图稿',
    GroupType.screenshot: '截图',
    GroupType.duplicate: '重复',
    GroupType.longShot: '长图',
    GroupType.mixed: '相似',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      color: highlight ? cs.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.savings_outlined,
                    color: highlight ? cs.onPrimaryContainer : cs.primary),
                const SizedBox(width: 8),
                Text(
                  '释放 ${report.freedLabel}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  DateFormat('M月d日 HH:mm').format(report.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _Metric(label: '删除', value: '${report.deletedCount} 张'),
                _Metric(label: '保留', value: '${report.keptCount} 张'),
                _Metric(label: '处理组', value: '${report.groupCount} 组'),
              ],
            ),
            if (report.categoryCounts.isNotEmpty) ...[
              const Divider(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: report.categoryCounts.entries
                    .map((e) => Chip(
                          label: Text(
                            '${_typeLabels[e.key] ?? e.key.name} × ${e.value}',
                            style: theme.textTheme.labelSmall,
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
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
