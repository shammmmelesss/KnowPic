import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/ios_design.dart';
import '../models/group_type.dart';
import '../models/similar_group.dart';
import 'ios_ui.dart';
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

  IconData _icon(Brightness b) {
    switch (group.type) {
      case GroupType.burst:
        return CupertinoIcons.camera_fill;
      case GroupType.editHistory:
        return CupertinoIcons.slider_horizontal_3;
      case GroupType.screenshot:
        return CupertinoIcons.crop;
      case GroupType.duplicate:
        return CupertinoIcons.doc_on_doc;
      case GroupType.longShot:
        return CupertinoIcons.rectangle_on_rectangle;
      case GroupType.mixed:
        return CupertinoIcons.photo_on_rectangle;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final previews = memberIds.take(3).toList();

    return IosCard(
      onTap: onTap,
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
                        borderRadius:
                            BorderRadius.circular(Ios.radiusThumb),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_icon(b), size: 17, color: Ios.blue(b)),
                    const SizedBox(width: 5),
                    Text(group.type.label, style: theme.textTheme.titleSmall),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${group.size} 张 · ${Ios.formatBytes(group.totalBytes)}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    IosBadge(
                      label: '可释放 ${Ios.formatBytes(reclaimableBytes)}',
                      color: Ios.blue(b).withValues(alpha: 0.12),
                      fg: Ios.blue(b),
                    ),
                    if (group.bestId.isNotEmpty)
                      IosBadge(
                        label: 'AI 最佳',
                        icon: CupertinoIcons.star_fill,
                        color: Ios.orange(b).withValues(alpha: 0.15),
                        fg: Ios.orange(b),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (onClean != null)
            CupertinoButton(
              minimumSize: const Size(44, 44),
              padding: const EdgeInsets.all(6),
              onPressed: onClean,
              child: Icon(CupertinoIcons.wand_stars,
                  size: 22, color: Ios.blue(b)),
            ),
        ],
      ),
    );
  }
}
