import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../core/haptics.dart';
import '../core/ios_design.dart';
import '../models/photo_asset.dart';
import '../models/user_action.dart';
import '../providers/providers.dart';
import '../widgets/ios_ui.dart';
import '../widgets/photo_thumb.dart';
import 'photo_viewer_screen.dart';

/// 相似组详情页（对应文档 9.3 核心操作流程 / 10 UI 状态机）
/// 叠图轮播 + 底部缩略图流 + 一键清理 + 隐式反馈采集。
class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  final PageController _controller = PageController();
  final Set<String> _keepIds = {};
  final Map<String, DateTime> _viewStart = {};
  bool _initialized = false;
  int _currentIndex = 0;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetsControllerProvider);
    final groups = ref.watch(groupsControllerProvider);
    final ranking = ref.watch(rankingProvider);
    final theme = Theme.of(context);
    final b = theme.brightness;

    final group = groups.where((g) => g.groupId == widget.groupId).firstOrNull;
    if (group == null) {
      return Scaffold(
        appBar: frostedAppBar(context),
        body: const Center(child: Text('该分组已清理')),
      );
    }

    // 按综合分排序（首位即 AI 最佳）
    final members = ranking.sortGroup(
      group.assetIds.map((id) => assets[id]).whereType<PhotoAsset>().toList(),
    );
    if (!_initialized) {
      _initialized = true;
      _keepIds
        ..clear()
        ..addAll(group.bestId.isEmpty ? <String>[] : {group.bestId});
    }
    if (_currentIndex >= members.length) _currentIndex = members.length - 1;

    final best = members.isEmpty ? null : members.first;
    final bestReason = best == null || members.length < 2
        ? '唯一选择'
        : ranking.bestReason(best, members, groupType: group.type);
    final keepCount = _keepIds.length;
    final freedBytes = members
        .where((m) => !_keepIds.contains(m.id))
        .fold<int>(0, (sum, m) => sum + m.byteSize);

    return PopScope(
      // 清理进行中禁止返回：软删到一半离开会让用户不知道到底删没删
      canPop: !_busy,
      child: Scaffold(
      appBar: frostedAppBar(
        context,
        title: '${group.type.label}（${members.length} 张）',
      ),
      body: Column(
        children: [
          // 顶部汇总
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Text('已选保留 $keepCount/${members.length} 张',
                    style: theme.textTheme.titleSmall),
                const Spacer(),
                Text(
                  '预计释放 ${Ios.formatBytes(freedBytes)}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: Ios.blue(b)),
                ),
              ],
            ),
          ),
          // 叠图轮播
          Expanded(
            child: members.isEmpty
                ? Center(
                    child: Text('暂无照片', style: theme.textTheme.bodyMedium))
                : Stack(
                    children: [
                      PageView.builder(
                        controller: _controller,
                        itemCount: members.length,
                        onPageChanged: (i) => _onPageChanged(members, i),
                        itemBuilder: (context, i) => _CarouselPhoto(
                          asset: members[i],
                          isBest: i == 0 && members.length > 1,
                          bestReason: i == 0 ? bestReason : null,
                          kept: _keepIds.contains(members[i].id),
                          onToggleKeep: () => _toggleKeep(members[i].id),
                          onZoom: () => _openViewer(members, i),
                        ),
                      ),
                      // 左右切换指示
                      Positioned(
                        left: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _OverlayCircleButton(
                            icon: CupertinoIcons.chevron_left,
                            enabled: !_busy && _currentIndex > 0,
                            onTap: _currentIndex > 0
                                ? () => _selectPage(_currentIndex - 1)
                                : null,
                          ),
                        ),
                      ),
                      Positioned(
                        right: 12,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _OverlayCircleButton(
                            icon: CupertinoIcons.chevron_right,
                            enabled: !_busy && _currentIndex < members.length - 1,
                            onTap: _currentIndex < members.length - 1
                                ? () => _selectPage(_currentIndex + 1)
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          // 底部缩略图流
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: members.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final m = members[i];
                final kept = _keepIds.contains(m.id);
                final selected = i == _currentIndex;
                return GestureDetector(
                  onTap: () => _selectPage(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? Ios.blue(b)
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: 60,
                          height: 60,
                          child: PhotoThumb(
                            key: ValueKey(m.id),
                            assetId: m.id,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        // 视觉圆点 20pt，命中区撑到 44pt（贴住缩略图右下角，
                        // 不越出 60×60 的缩略图边界以免被 Stack 裁掉）：
                        // 原先是 20×20 的裸热点，紧贴「切页」热点，极易误触
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _toggleKeep(m.id),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Align(
                                alignment: Alignment.center,
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: kept
                                        ? Ios.red(b)
                                        : Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    kept
                                        ? CupertinoIcons.heart_fill
                                        : CupertinoIcons.trash,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (m.id == group.bestId)
                          Positioned(
                            left: 2,
                            top: 2,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                CupertinoIcons.star_fill,
                                size: 10,
                                color: Ios.orange(b),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 操作栏
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoButton(
                      color: Ios.fill(b),
                      borderRadius:
                          BorderRadius.circular(Ios.radiusCard),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _keepIds.addAll(members.map((m) => m.id));
                              }),
                      child: Text(
                        '全部保留',
                        style: TextStyle(
                          color: Ios.label(b),
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoButton.filled(
                      borderRadius:
                          BorderRadius.circular(Ios.radiusCard),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      onPressed: _busy || keepCount == members.length
                          ? null
                          : () => _clean(group.groupId, members),
                      child: _busy
                          ? const CupertinoActivityIndicator(
                              color: Colors.white)
                          : Text(
                              '一键清理${freedBytes > 0 ? '（${Ios.formatBytes(freedBytes)}）' : ''}',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _toggleKeep(String id) {
    if (_busy) return; // 清理进行中：保留集合已定死，再改会与真实结果脱节
    Haptics.selection();
    setState(() {
      if (_keepIds.contains(id)) {
        _keepIds.remove(id);
      } else {
        _keepIds.add(id);
      }
    });
  }

  void _selectPage(int index) {
    if (_busy) return;
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// 打开全屏预览放大对比（此前双击只弹提示、画面不动）
  Future<void> _openViewer(List<PhotoAsset> members, int index) async {
    if (_busy || members.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerScreen(
          assets: members,
          initialIndex: index,
          // 真正发生放大才算强正样本，而不是点一下就记
          onZoomed: (asset) => ref.read(learningProvider).collect(UserAction(
                assetId: asset.id,
                groupId: widget.groupId,
                type: ActionType.zoomIn,
                timestamp: DateTime.now(),
              )),
        ),
      ),
    );
  }

  void _onPageChanged(List<PhotoAsset> members, int index) {
    // 隐式反馈：停留 >1.5s → 正样本；快速划走 → 负样本（文档 8.2）
    final now = DateTime.now();
    final start = _viewStart[members[_currentIndex].id];
    if (start != null) {
      final dwell = now.difference(start).inMilliseconds / 1000.0;
      ref.read(learningProvider).collect(UserAction(
            assetId: members[_currentIndex].id,
            groupId: widget.groupId,
            type: dwell >= AppConfig.positiveViewDuration
                ? ActionType.viewLong
                : ActionType.viewShort,
            timestamp: now,
          ));
    }
    setState(() => _currentIndex = index);
    _viewStart[members[index].id] = now;
  }

  Future<void> _clean(String groupId, List<PhotoAsset> members) async {
    final settings = ref.read(settingsProvider);
    final deletedIds = members
        .where((m) => !_keepIds.contains(m.id))
        .map((m) => m.id)
        .toList();
    if (deletedIds.isEmpty) return;

    // 二次确认（文档 9.3 / 9.5 安全机制）
    if (settings.confirmBeforeDelete) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('确认清理？'),
          content: Text(
            '将删除 ${deletedIds.length} 张照片（释放约 ${Ios.formatBytes(deletedIds.fold<int>(0, (s, id) => s + (members.firstWhere((m) => m.id == id).byteSize)))}）。\n\n已删除照片会进入回收站，保留 30 天，可随时还原。',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认清理'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busy = true);
    final store = ref.read(storeProvider);
    final byId = ref.read(assetsControllerProvider);
    final learning = ref.read(learningProvider);
    final report = ref.read(reportProvider);
    final group = ref
        .read(groupsControllerProvider)
        .where((g) => g.groupId == groupId)
        .firstOrNull;

    try {
      // 1. 软删除（备份 → 移入回收站 → 系统删除）
      final result = await ref.read(trashProvider).softDelete(deletedIds, byId);

      // 仅真正从系统相册删除的才算已清理：云端跳过 / 系统删除失败（如用户在系统弹窗取消）的照片仍在相册中
      final notDeleted = {...result.skippedIds, ...result.failedIds};
      final actuallyDeleted =
          deletedIds.where((id) => !notDeleted.contains(id)).toList();
      if (actuallyDeleted.isEmpty) {
        if (mounted) {
          Haptics.warning();
          showIosToast(context, result.failedIds.isNotEmpty
              ? '未删除任何照片（系统删除被取消或失败）'
              : '未删除任何照片（云端照片尚未下载到本机）');
          setState(() => _busy = false);
        }
        return;
      }

      // 2. 记录显式反馈（文档 8.2）
      // 用进入清理时的快照：清理期间界面已锁定，快照保证反馈与实际删除集合一致
      final keepSnapshot = Set<String>.from(_keepIds);
      final now = DateTime.now();
      for (final id in keepSnapshot) {
        learning.collect(UserAction(
            assetId: id, groupId: groupId, type: ActionType.keep, timestamp: now));
      }
      for (final id in actuallyDeleted) {
        learning.collect(UserAction(
            assetId: id, groupId: groupId, type: ActionType.delete, timestamp: now));
      }
      await learning.flush();

      // 3. 反漏斗追踪
      if (group != null) {
        learning.recordGroupOutcome(groupId, group.bestId, keepSnapshot.toList());
      }

      // 4. 清理报告
      if (group != null) {
        report.recordClean(group, keepSnapshot.toList(), actuallyDeleted, byId);
      }

      // 5. 从元数据移除（仅已删除的；组内剩余不足 2 张则整组移除）
      for (final id in actuallyDeleted) {
        store.assets.remove(id);
      }
      if (group != null && notDeleted.isNotEmpty) {
        group.assetIds.removeWhere(actuallyDeleted.contains);
        group.totalBytes = group.assetIds
            .fold<int>(0, (s, id) => s + (byId[id]?.byteSize ?? 0));
      }
      store.groups.removeWhere((g) =>
          g.groupId == groupId && (notDeleted.isEmpty || g.assetIds.length < 2));
      await store.saveAssets();
      await store.saveGroups();

      if (mounted) {
        ref.read(assetsControllerProvider.notifier).reload();
        ref.read(groupsControllerProvider.notifier).reload();
      }

      // 6. 反漏斗挽救（文档 9.4）
      if (mounted && learning.consumeResetPrompt()) {
        await _showResetDialog();
      }

      if (mounted) {
        final skipped = result.skippedIds.length;
        final failed = result.failedIds.length;
        final message = skipped + failed > 0
            ? '已清理 ${actuallyDeleted.length} 张'
                '${skipped > 0 ? '，$skipped 张因云端未下载被跳过' : ''}'
                '${failed > 0 ? '，$failed 张系统删除失败' : ''}'
            : '已释放 ${Ios.formatBytes(result.freedBytes)}，可在回收站还原';
        showIosToast(context, message, success: true);
        Navigator.of(context).pop(result.freedBytes);
      }
    } catch (err) {
      if (mounted) {
        Haptics.warning();
        showIosToast(context, '清理失败：$err');
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _showResetDialog() async {
    final learning = ref.read(learningProvider);
    final reset = await showDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('看起来推荐不太对？'),
        content: const Text(
          'AI 已经连续多次推荐了您不喜欢的照片。是否重置偏好模型，重新学习您的喜好？',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('继续学习'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置偏好'),
          ),
        ],
      ),
    );
    if (reset == true) {
      await learning.confirmReset();
      if (mounted) {
        showIosToast(context, '偏好已重置，将重新学习您的喜好');
      }
    }
  }
}

/// 图片上的圆形毛玻璃操作按钮
class _OverlayCircleButton extends StatelessWidget {
  const _OverlayCircleButton({
    required this.icon,
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: IosPressable(
        onTap: enabled ? onTap : null,
        scale: 0.9,
        // 视觉圆 36pt，命中区 44pt
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Colors.black38,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 22, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// 叠图轮播单张（大图 + 状态角标 + 最佳徽章）
class _CarouselPhoto extends StatelessWidget {
  const _CarouselPhoto({
    required this.asset,
    required this.isBest,
    this.bestReason,
    required this.kept,
    required this.onToggleKeep,
    required this.onZoom,
  });

  final PhotoAsset asset;
  final bool isBest;
  final String? bestReason;
  final bool kept;
  final VoidCallback onToggleKeep;
  final VoidCallback onZoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: GestureDetector(
        onDoubleTap: onZoom,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Ios.radiusMedia),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PhotoThumb(
                key: ValueKey(asset.id),
                assetId: asset.id,
                fit: BoxFit.contain,
              ),
              // 顶部信息：AI 最佳徽章
              Positioned(
                top: 8,
                left: 8,
                child: Row(
                  children: [
                    if (isBest && bestReason != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.star_fill,
                                size: 13, color: Ios.orange(b)),
                            const SizedBox(width: 4),
                            Text(
                              bestReason!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              // 状态角标：保留/删除（视觉圆 36pt，命中区 44pt）
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleKeep,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: kept ? Ios.red(b) : Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          kept
                              ? CupertinoIcons.heart_fill
                              : CupertinoIcons.trash,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // 底部信息
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        DateFormat('yyyy年M月d日 HH:mm').format(asset.createdTime),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        asset.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 显式的放大入口：双击虽然也能放大，但手势不可见，用户找不到
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onZoom,
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: Center(
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              CupertinoIcons.zoom_in,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
