import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ios_design.dart';
import '../models/trash_item.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/ios_ui.dart';

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
    final b = theme.brightness;

    return Scaffold(
      appBar: frostedAppBar(
        context,
        title: '回收站',
        actions: [
          if (items.isNotEmpty)
            CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              onPressed: () => _emptyAll(),
              child: Text(
                '清空',
                style: TextStyle(color: Ios.red(b), fontSize: 17),
              ),
            ),
        ],
      ),
      body: items.isEmpty
          ? const EmptyState(
              icon: CupertinoIcons.trash,
              title: '回收站是空的',
              subtitle: '清理的照片会在这里保留 30 天，可随时还原',
            )
          : Column(
              children: [
                IosCard(
                  margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      '已删除照片保留 30 天，过期将自动彻底删除；还原后照片将回到系统相册。',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
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
    showIosToast(
      context,
      restored.isNotEmpty
          ? '已还原${item.isLivePhoto ? '（Live Photo 仅还原静态图）' : ''}'
          : '还原失败，请重试',
      success: restored.isNotEmpty,
    );
  }

  Future<void> _permanentDelete(TrashItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('彻底删除？'),
        content: const Text('此操作不可恢复，照片将被永久删除。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
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
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('清空回收站？'),
        content: const Text('将彻底删除回收站中的所有照片，此操作不可恢复。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final ids =
        ref.read(trashControllerProvider).map((t) => t.id).toList();
    await ref.read(trashProvider).permanentDelete(ids);
    if (mounted) {
      ref.read(trashControllerProvider.notifier).reload();
      showIosToast(context, '回收站已清空', success: true);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final b = theme.brightness;
    final urgent = item.remainingDays <= 5;

    return IosCard(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Ios.radiusThumb),
            child: Image.file(
              file,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              // 回收站里是原图，不约束解码尺寸会把整张原图展开成位图进 ImageCache
              cacheWidth:
                  (56 * MediaQuery.devicePixelRatioOf(context)).round(),
              errorBuilder: (_, _, _) => Container(
                width: 56,
                height: 56,
                color: cs.surfaceContainerHighest,
                child: Icon(CupertinoIcons.photo,
                    size: 20, color: Ios.tertiaryLabel(b)),
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
                const SizedBox(height: 3),
                Text(
                  '${Ios.formatBytes(item.byteSize)}${item.isLivePhoto ? ' · Live' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                IosBadge(
                  label: item.isExpired ? '已过期' : '还剩 ${item.remainingDays} 天',
                  color: urgent
                      ? Ios.red(b).withValues(alpha: 0.12)
                      : Ios.fill(b),
                  fg: urgent ? Ios.red(b) : Ios.secondaryLabel(b),
                ),
              ],
            ),
          ),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.all(6),
            onPressed: onRestore,
            child: Icon(CupertinoIcons.arrow_counterclockwise,
                size: 22, color: Ios.blue(b)),
          ),
          CupertinoButton(
            minimumSize: const Size(44, 44),
            padding: const EdgeInsets.all(6),
            onPressed: onDelete,
            child: Icon(CupertinoIcons.trash_fill,
                size: 22, color: Ios.red(b)),
          ),
        ],
      ),
    );
  }
}
