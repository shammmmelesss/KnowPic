import 'package:flutter/material.dart';

import '../models/group_type.dart';
import '../models/similar_group.dart';
import 'photo_thumb.dart';

/// 相似组卡片（分组列表项）
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.group,
    required this.memberIds,
    required this.reclaimableBytes,
    this.onTap,
    this.onClean,
  });

  final SimilarGroup group;
  final List<String> memberIds; // 按综合分降序（首位为 AI 最佳）
  final int reclaimableBytes;
  final VoidCallback? onTap;
  final VoidCallback? onClean;

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  IconData get _icon {
    switch (group.type) {
      case GroupType.burst:
        return Icons.camera_alt;
      case GroupType.editHistory:
        return Icons.tune;
      case GroupType.screenshot:
        return Icons.screenshot_monitor;
      case GroupType.duplicate:
        return Icons.content_copy;
      case GroupType.longShot:
        return Icons.landscape;
      case GroupType.mixed:
        return Icons.collections;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final previews = memberIds.take(3).toList();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // 叠图缩略图
              SizedBox(
                width: 88,
                height: 88,
                child: Stack(
                  children: [
                    for (var i = previews.length - 1; i >= 0; i--)
                      Positioned(
                        left: i * 6.0,
                        top: i * 6.0,
                        child: SizedBox(
                          width: 76,
                          height: 76,
                          child: PhotoThumb(
                            assetId: previews[i],
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_icon, size: 18, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          group.type.label,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${group.size} 张 · ${_formatBytes(group.totalBytes)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '可释放 ${_formatBytes(reclaimableBytes)}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (group.bestId.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '👑 AI 最佳',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onTertiaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (onClean != null)
                IconButton(
                  onPressed: onClean,
                  icon: const Icon(Icons.cleaning_services_outlined),
                  tooltip: '一键清理',
                ),
            ],
          ),
        ),
      ),
    );
  }
}
