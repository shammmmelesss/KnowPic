import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/photo_asset.dart';
import '../providers/providers.dart';
import '../services/memory_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/photo_thumb.dart';

/// 记忆盲盒 & 那年今日（对应文档 Phase 3 生态与体验）
class MemoriesScreen extends ConsumerStatefulWidget {
  const MemoriesScreen({super.key});

  @override
  ConsumerState<MemoriesScreen> createState() => _MemoriesScreenState();
}

class _MemoriesScreenState extends ConsumerState<MemoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: '记忆盲盒'),
            Tab(text: '那年今日'),
          ],
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
    setState(() {
      _picked = picked;
      _count++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assets = ref.watch(assetsControllerProvider);

    if (assets.isEmpty) {
      return const EmptyState(
        icon: Icons.auto_awesome_outlined,
        title: '先扫描相册',
        subtitle: '扫描完成后即可抽取记忆盲盒',
      );
    }

    if (_picked.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cake_outlined,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            const Text('随机翻开一段旧时光'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('抽取一张'),
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
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PhotoThumb(assetId: photo.id, fit: BoxFit.contain),
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
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
          FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.refresh),
            label: const Text('再来一个'),
          ),
          if (_count > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '已抽取 $_count 次',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
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
        icon: Icons.history,
        title: '今天没有往年照片',
        subtitle: '历史上的今天暂无照片，明天再来看看',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: photos.length,
      itemBuilder: (context, i) {
        final p = photos[i];
        return Stack(
          fit: StackFit.expand,
          children: [
            PhotoThumb(assetId: p.id, borderRadius: BorderRadius.circular(8)),
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
        );
      },
    );
  }
}
