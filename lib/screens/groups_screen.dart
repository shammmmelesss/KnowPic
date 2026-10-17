import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ios_design.dart';
import '../l10n/app_strings_delegate.dart';
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

    final l10n = context.l10n;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // 二级页按 iOS 惯例居中标题，同样去掉大标题的整块留白
          frostedSliverAppBar(context,
              title: l10n.groupsTitle, centerTitle: true),
          if (groups.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: CupertinoIcons.photo_on_rectangle,
                title: l10n.groupsEmptyTitle,
                subtitle: l10n.groupsEmptySubtitle,
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
                                l10n.groupsSummary(
                                    groups.length, Ios.formatBytes(totalReclaim)),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final g = groups[i - 1];
                    // 成员与可释放空间在此解析：原实现让每张卡片各自 watch 整个分组
                    // 列表再线性查找，是 O(n²) 且任何变更都会重建全部卡片
                    final memberIds = g.assetIds
                        .where((id) => assets.containsKey(id))
                        .toList();
                    return Padding(
                      // 用 groupId 作 Key：用索引会让清理后新增/删除的组错位复用
                      key: ValueKey(g.groupId),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GroupCard(
                        group: g,
                        memberIds: memberIds,
                        reclaimableBytes:
                            similarity.estimateReclaimable(g, assets),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                GroupDetailScreen(groupId: g.groupId),
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
