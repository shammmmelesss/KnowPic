import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/constants.dart';
import '../providers/providers.dart';

/// 设置页（隐私/偏好模型管理）
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final permission = ref.watch(permissionControllerProvider);
    final learning = ref.watch(learningProvider);
    final model = learning.model;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          _Section(
            title: '相册权限',
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('访问状态'),
                subtitle: Text(permission ? '已授权' : '未授权'),
                trailing: permission
                    ? null
                    : FilledButton(
                        onPressed: () => ref
                            .read(permissionControllerProvider.notifier)
                            .request(),
                        child: const Text('去授权'),
                      ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  '隐私承诺：所有分析均在手机本地完成，图片绝不联网上传；可随时在系统设置中改为"部分照片"访问。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
          _Section(
            title: '个人偏好模型',
            children: [
              ListTile(
                leading: const Icon(Icons.psychology_outlined),
                title: const Text('已学习样本'),
                subtitle: Text(model.isTrained
                    ? '${model.sampleCount} 条 · ${model.resetCount == 0 ? '从未重置' : '已重置 ${model.resetCount} 次'}'
                    : '尚无样本，冷启动中（纯客观评分）'),
              ),
              ListTile(
                leading: const Icon(Icons.landscape_outlined),
                title: const Text('场景偏好'),
                subtitle: const Text('人像/风景/截图等分别独立学习'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showSceneDetail(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.update),
                title: const Text('最近更新'),
                subtitle: Text(model.lastUpdated == null
                    ? '—'
                    : DateFormat('yyyy年M月d日 HH:mm').format(model.lastUpdated!)),
              ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('导出偏好'),
                subtitle: const Text('加密偏好文件（几 KB），可自行备份迁移'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _exportPref(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('重置偏好'),
                subtitle: const Text('清空所有场景的学习结果，退回客观排序'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _resetPref(context, ref),
              ),
            ],
          ),
          _Section(
            title: '隐私与数据',
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.insights_outlined),
                title: const Text('帮助改进产品'),
                subtitle: const Text('仅上传脱敏统计（采纳率等），不含任何图片信息'),
                value: settings.helpImprove,
                onChanged: (v) =>
                    ref.read(settingsProvider.notifier).toggleHelpImprove(v),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.shield_outlined),
                title: const Text('清理前二次确认'),
                subtitle: const Text('默认开启，防误删'),
                value: settings.confirmBeforeDelete,
                onChanged: (v) => ref
                    .read(settingsProvider.notifier)
                    .toggleConfirmBeforeDelete(v),
              ),
            ],
          ),
          _Section(
            title: '关于',
            children: const [
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('KnowPic 智能相册整理助手'),
                subtitle: Text('版本 1.0.0 · 全本地离线 · 隐私第一'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showSceneDetail(BuildContext context, WidgetRef ref) async {
    final learning = ref.read(learningProvider);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('场景偏好详情'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  '每个场景独立学习您的审美（FTRL），互不干扰：',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
              for (final entry in learning.models.entries) ...[
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    entry.key == AppConfig.defaultScene
                        ? Icons.auto_awesome
                        : Icons.photo_outlined,
                    size: 20,
                  ),
                  title: Text(AppConfig.sceneLabel(entry.key)),
                  trailing: Text(
                    '${entry.value.sampleCount} 条${entry.value.isTrained ? '' : '（冷启动）'}',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
                const Divider(height: 1),
              ],
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '全局模型汇总所有场景样本，供跨场景兜底。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    }
  }

  Future<void> _resetPref(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置偏好模型？'),
        content: const Text('将清空已学习的个人偏好，恢复为纯客观评分排序。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重置'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await ref.read(learningProvider).confirmReset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('偏好已重置')),
        );
      }
    }
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: children),
        ),
      ],
    );
  }
}
