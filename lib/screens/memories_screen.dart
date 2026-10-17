import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/haptics.dart';
import '../core/ios_design.dart';
import '../models/photo_asset.dart';
import '../providers/providers.dart';
import '../services/memory_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/ios_ui.dart';
import '../widgets/photo_thumb.dart';
import 'photo_viewer_screen.dart';

/// 打开全屏查看器（盲盒页与那年今日页共用）
void _openViewer(BuildContext context, List<PhotoAsset> photos, int index) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PhotoViewerScreen(assets: photos, initialIndex: index),
    ),
  );
}

/// 记忆盲盒 & 那年今日（对应文档 Phase 3 生态与体验）
class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);
  int _seg = 0;

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    if (_seg != _tab.index) {
      setState(() => _seg = _tab.index);
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;

    return Scaffold(
      appBar: frostedAppBar(
        context,
        title: '记忆',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: SizedBox(
              width: 220,
              height: 32,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _seg,
                backgroundColor: Ios.fill(b),
                thumbColor: Ios.card(b),
                children: {
                  0: Text('记忆盲盒', style: theme.textTheme.bodySmall),
                  1: Text('那年今日', style: theme.textTheme.bodySmall),
                },
                onValueChanged: (v) {
                  if (v == null || v == _seg) return;
                  Haptics.selection();
                  setState(() => _seg = v);
                  _tab.animateTo(
                    v,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
              ),
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _BlindBoxTab(),
          _TodayInHistoryTab(),
        ],
      ),
    );
  }
}

class _BlindBoxTab extends ConsumerStatefulWidget {
  const _BlindBoxTab();

  @override
  ConsumerState<_BlindBoxTab> createState() => _BlindBoxTabState();
}

class _BlindBoxTabState extends ConsumerState<_BlindBoxTab> {
  List<PhotoAsset> _picked = const [];
  int _count = 0;

  void _pick() {
    final assets = ref.read(assetsControllerProvider);
    final picked = MemoryService.pickBlindBox(assets, count: 1);
    if (picked.isEmpty) {
      // 抽签池为空（没有 90 天以上的老照片）：不能发成功触感更不能静默无反应
      Haptics.warning();
      showIosToast(context, '暂无可抽取的老照片（需要 90 天以上的照片）');
      return;
    }
    Haptics.success();
    setState(() {
      _picked = picked;
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final assets = ref.watch(assetsControllerProvider);

    if (assets.isEmpty) {
      return const EmptyState(
        icon: CupertinoIcons.sparkles,
        title: '先扫描相册',
        subtitle: '扫描完成后即可抽取记忆盲盒',
      );
    }

    if (_picked.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.gift, size: 64, color: Ios.blue(b)),
            const SizedBox(height: 16),
            Text('随机翻开一段旧时光',
                style: theme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            CupertinoButton.filled(
              onPressed: _pick,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(CupertinoIcons.sparkles, size: 18),
                  SizedBox(width: 8),
                  Text('抽取一张'),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final photo = _picked.first;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Ios.radiusMedia),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: () => _openViewer(context, [photo], 0),
                    child: PhotoThumb(
                      key: ValueKey(photo.id),
                      assetId: photo.id,
                      fit: BoxFit.contain,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        DateFormat('yyyy年M月d日').format(photo.createdTime),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          CupertinoButton.filled(
            onPressed: _pick,
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(CupertinoIcons.refresh, size: 18),
                SizedBox(width: 8),
                Text('再来一个'),
              ],
            ),
          ),
          if (_count > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已抽取 $_count 次',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: Ios.tertiaryLabel(b)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayInHistoryTab extends ConsumerWidget {
  const _TodayInHistoryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(assetsControllerProvider);
    final photos = MemoryService.todayInHistory(assets, DateTime.now());

    if (photos.isEmpty) {
      return const EmptyState(
        icon: CupertinoIcons.clock,
        title: '今天没有往年照片',
        subtitle: '历史上的今天暂无照片，明天再来看看',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: photos.length,
      itemBuilder: (context, i) {
        final p = photos[i];
        return GestureDetector(
          key: ValueKey(p.id),
          onTap: () => _openViewer(context, photos, i),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PhotoThumb(
                  assetId: p.id,
                  borderRadius: BorderRadius.circular(Ios.radiusThumb)),
              Positioned(
                left: 4,
                bottom: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${p.createdTime.year}年',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
