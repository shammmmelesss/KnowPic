import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ios_design.dart';
import '../models/photo_asset.dart';
import '../providers/providers.dart';
import '../widgets/empty_state.dart';
import '../widgets/group_card.dart';
import '../widgets/ios_ui.dart';
import 'group_detail_screen.dart';

/// 相似组列表页
class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsControllerProvider);
    final assets = ref.watch(assetsControllerProvider);
    final similarity = ref.watch(similarityProvider);
    final b = Theme.of(context).brightness;

    final totalReclaim = groups.fold<int>(
      0,
      (sum, g) => sum + similarity.estimateReclaimable(g, assets),
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: const Text('相似组'),
            backgroundColor: Colors.transparent,
            flexibleSpace: frostedBar(context),
          ),
          if (groups.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: CupertinoIcons.photo_on_rectangle,
                title: '还没有相似组',
                subtitle: '回到首页点击「开始扫描」，自动识别连拍、截图与重复照片',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) {
                    if (i == 0) {
                      return IosCard(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(CupertinoIcons.photo_on_rectangle,
                                color: Ios.blue(b), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '共 ${groups.length} 组相似照片，一键清理可释放约 ${Ios.formatBytes(totalReclaim)}',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final g = groups[i - 1];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _GroupCardView(
                        groupId: g.groupId,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupDetailScreen(groupId: g.groupId),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: groups.length + 1,
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
