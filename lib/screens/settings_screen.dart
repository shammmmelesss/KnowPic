import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../core/haptics.dart';
import '../core/ios_design.dart';
import '../providers/providers.dart';
import '../widgets/ios_ui.dart';

/// 设置页（隐私/偏好模型管理，iOS 分组列表样式）
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final permission = ref.watch(permissionControllerProvider);
    final learning = ref.watch(learningProvider);
    final model = learning.model;
    final theme = Theme.of(context);
    final b = theme.brightness;
    final blue = Ios.blue(b);

    return Scaffold(
      appBar: frostedAppBar(context, title: '设置'),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          CupertinoListSection.insetGrouped(
            header: const Text('相册权限'),
            footer: const Text(
              '隐私承诺：所有分析均在手机本地完成，图片绝不联网上传；可随时在系统设置中改为「部分照片」访问。',
            ),
            children: [
              CupertinoListTile(
                leading: Icon(CupertinoIcons.photo_on_rectangle,
                    color: blue, size: 24),
                title: const Text('访问状态'),
                subtitle: Text(permission ? '已授权' : '未授权'),
                trailing: permission
                    ? null
                    : CupertinoButton.filled(
                        minimumSize: const Size(44, 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        onPressed: () => ref
                            .read(permissionControllerProvider.notifier)
                            .request(),
                        child: const Text('去授权'),
                      ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('个人偏好模型'),
            children: [
              CupertinoListTile(
                leading: Icon(CupertinoIcons.sparkles, color: blue, size: 24),
                title: const Text('已学习样本'),
                subtitle: Text(model.isTrained
                    ? '${model.sampleCount} 条 · ${model.resetCount == 0 ? '从未重置' : '已重置 ${model.resetCount} 次'}'
                    : '尚无样本，冷启动中（纯客观评分）'),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.camera_viewfinder,
                    color: blue, size: 24),
                title: const Text('场景偏好'),
                subtitle: const Text('人像/风景/截图等分别独立学习'),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _showSceneDetail(context, ref),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.clock, color: blue, size: 24),
                title: const Text('最近更新'),
                subtitle: Text(model.lastUpdated == null
                    ? '—'
                    : DateFormat('yyyy年M月d日 HH:mm').format(model.lastUpdated!)),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.share, color: blue, size: 24),
                title: const Text('导出偏好'),
                subtitle: const Text('加密偏好文件（几 KB），可自行备份迁移'),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _exportPref(context, ref),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.arrow_counterclockwise,
                    color: Ios.red(b), size: 24),
                title: const Text('重置偏好'),
                subtitle: const Text('清空所有场景的学习结果，退回客观排序'),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _resetPref(context, ref),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('隐私与数据'),
            children: [
              CupertinoListTile(
                leading: Icon(CupertinoIcons.chart_bar, color: blue, size: 24),
                title: const Text('帮助改进产品'),
                subtitle: const Text('仅上传脱敏统计（采纳率等），不含任何图片信息'),
                trailing: CupertinoSwitch(
                  value: settings.helpImprove,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).toggleHelpImprove(v),
                ),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.shield, color: blue, size: 24),
                title: const Text('清理前二次确认'),
                subtitle: const Text('默认开启，防误删'),
                trailing: CupertinoSwitch(
                  value: settings.confirmBeforeDelete,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .toggleConfirmBeforeDelete(v),
                ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('关于'),
            children: [
              CupertinoListTile(
                leading: Icon(CupertinoIcons.info, color: blue, size: 24),
                title: const Text('KnowPic 智能相册整理助手'),
                subtitle: const Text('版本 1.0.0 · 全本地离线 · 隐私第一'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showSceneDetail(BuildContext context, WidgetRef ref) async {
    final learning = ref.read(learningProvider);
    final theme = Theme.of(context);
    final b = theme.brightness;
    await showDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('场景偏好详情'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  '每个场景独立学习您的审美（FTRL），互不干扰：',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                for (final entry in learning.models.entries) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            AppConfig.sceneLabel(entry.key),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${entry.value.sampleCount} 条${entry.value.isTrained ? '' : '（冷启动）'}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Ios.secondaryLabel(b)),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: Ios.separator(b)),
                ],
                const SizedBox(height: 8),
                Text(
                  '全局模型汇总所有场景样本，供跨场景兜底。',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Ios.tertiaryLabel(b)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportPref(BuildContext context, WidgetRef ref) async {
    final store = ref.read(storeProvider);
    final file = store.prefFile;
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'application/json')],
        text: 'KnowPic 偏好模型导出（请妥善保管）',
      ));
    } catch (e) {
      if (context.mounted) {
        showIosToast(context, '导出失败：$e');
      }
    }
  }

  Future<void> _resetPref(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('重置偏好模型？'),
        content: const Text('将清空已学习的个人偏好，恢复为纯客观评分排序。'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Haptics.warning();
      await ref.read(learningProvider).confirmReset();
      if (context.mounted) {
        showIosToast(context, '偏好已重置', success: true);
      }
    }
  }
}
