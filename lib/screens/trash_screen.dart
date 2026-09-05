import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/trash_item.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';

/// 回收站（对应文档 9.5 安全机制：保留 30 天、一键还原）
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  bool _cleaned = false;

  @override
  void initState() {
    super.initState();
    // 启动时清理过期文件（文档 7.6 realClean）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_cleaned) return;
      _cleaned = true;
      await ref.read(trashProvider).realClean();
      if (mounted) {
        ref.read(trashControllerProvider.notifier).reload();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(trashControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (items.isNotEmpty)
            TextButton(
              onPressed: () => _emptyAll(),
              child: const Text('清空回收站'),
            ),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: Icons.delete_outline,
              title: '回收站是空的',
              subtitle: '清理的照片会在这里保留 30 天，可随时还原',
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: theme.colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '已删除照片保留 30 天，过期将自动彻底删除；还原后照片将回到系统相册。',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final file =
                          ref.read(storeProvider).trashFileOf(items[i]);
                      return _TrashItemCard(
                        item: items[i],
                        file: file,
                        onRestore: () => _restore(items[i]),
                        onDelete: () => _permanentDelete(items[i]),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _restore(TrashItem item) async {
    final restored = await ref.read(trashProvider).restore([item.id]);
    if (!mounted) return;
    ref.read(trashControllerProvider.notifier).reload();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          restored.isNotEmpty
              ? '已还原${item.isLivePhoto ? '（Live Photo 仅还原静态图）' : ''}'
              : '还原失败，请重试',
        ),
      ));
  }

  Future<void> _permanentDelete(TrashItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('彻底删除？'),
        content: const Text('此操作不可恢复，照片将被永久删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('彻底删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(trashProvider).permanentDelete([item.id]);
    if (mounted) {
      ref.read(trashControllerProvider.notifier).reload();
    }
  }

  Future<void> _emptyAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站？'),
        content: const Text('将彻底删除回收站中的所有照片，此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ids = ref
        .read(trashControllerProvider)
        .map((t) => t.id)
        .toList();
    await ref.read(trashProvider).permanentDelete(ids);
    if (mounted) {
      ref.read(trashControllerProvider.notifier).reload();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('回收站已清空')),
      );
    }
  }
}

class _TrashItemCard extends StatelessWidget {
  const _TrashItemCard({
    required this.item,
    required this.file,
    required this.onRestore,
    required this.onDelete,
  });

  final TrashItem item;
  final File file;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  String _fmt(int bytes) {
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
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                file,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 64,
                  height: 64,
                  color: cs.surfaceContainerHighest,
                  child: const Icon(Icons.image_not_supported_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.originalTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_fmt(item.byteSize)}${item.isLivePhoto ? ' · Live' : ''}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.remainingDays <= 5
                          ? cs.errorContainer
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      item.isExpired ? '已过期' : '还剩 ${item.remainingDays} 天',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: item.remainingDays <= 5
                            ? cs.onErrorContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRestore,
              icon: const Icon(Icons.settings_backup_restore),
              tooltip: '还原',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_forever_outlined),
              tooltip: '彻底删除',
            ),
          ],
        ),
      ),
    );
  }
}
