import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/photo_asset.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/group_card.dart';
import 'group_detail_screen.dart';

/// 相似组列表页
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsControllerProvider);
    final assets = ref.watch(assetsControllerProvider);
    final similarity = ref.watch(similarityProvider);

    final totalReclaim = groups.fold<int>(
      0,
      (sum, g) => sum + similarity.estimateReclaimable(g, assets),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('相似组')),
      body: groups.isEmpty
          ? const EmptyState(
              icon: Icons.collections_outlined,
              title: '还没有相似组',
              subtitle: '回到首页点击"开始扫描"，自动识别连拍、截图与重复照片',
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.storage_outlined,
                            color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '共 ${groups.length} 组相似照片，一键清理可释放约 $totalReclaim',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                for (final g in groups)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _GroupCardView(
                      groupId: g.groupId,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupDetailScreen(groupId: g.groupId),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _GroupCardView extends ConsumerWidget {
  const _GroupCardView({required this.groupId, this.onTap});

  final String groupId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsControllerProvider);
    final assets = ref.watch(assetsControllerProvider);
    final similarity = ref.watch(similarityProvider);

    final group = groups.where((g) => g.groupId == groupId).firstOrNull;
    if (group == null) return const SizedBox.shrink();

    final members = group.assetIds
        .map((id) => assets[id])
        .whereType<PhotoAsset>()
        .toList();
    final reclaim = similarity.estimateReclaimable(group, assets);

    return GroupCard(
      group: group,
      memberIds: members.map((m) => m.id).toList(),
      reclaimableBytes: reclaim,
      onTap: onTap,
    );
  }
}
