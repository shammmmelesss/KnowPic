import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/haptics.dart';
import '../core/ios_design.dart';
import '../l10n/app_strings.dart';
import '../l10n/app_strings_delegate.dart';
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
    final l10n = context.l10n;

    // 选中项看设置值，脚注展示实际生效的语言（跟随系统时解析结果）
    final selected = AppLanguage.fromCode(settings.languageMode);
    final effective =
        AppLanguage.fromCode(ref.watch(localeProvider).languageCode);

    return Scaffold(
      appBar: frostedAppBar(context, title: l10n.settings),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          CupertinoListSection.insetGrouped(
            header: Text(l10n.photoPermission),
            footer: Text(l10n.privacyFooter),
            children: [
              CupertinoListTile(
                leading: Icon(CupertinoIcons.photo_on_rectangle,
                    color: blue, size: 24),
                title: Text(l10n.accessStatus),
                subtitle: Text(permission ? l10n.authorized : l10n.unauthorized),
                trailing: permission
                    ? null
                    : CupertinoButton.filled(
                        minimumSize: const Size(44, 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        onPressed: () => ref
                            .read(permissionControllerProvider.notifier)
                            .request(),
                        child: Text(l10n.grantAction),
                      ),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: Text(l10n.language),
            footer: Text(l10n.languageFooter(l10n.languageName(effective))),
            children: [
              for (final lang in AppLanguage.values)
                CupertinoListTile(
                  leading: Icon(CupertinoIcons.globe, color: blue, size: 24),
                  title: Text(l10n.languageName(lang)),
                  trailing: lang == selected
                      ? Icon(CupertinoIcons.check_mark,
                          color: blue, size: 20)
                      : null,
                  onTap: () => ref
                      .read(settingsProvider.notifier)
                      .setLanguageMode(lang.code),
                ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: Text(l10n.prefModel),
            children: [
              CupertinoListTile(
                leading: Icon(CupertinoIcons.sparkles, color: blue, size: 24),
                title: Text(l10n.learnedSamples),
                subtitle: Text(model.isTrained
                    ? l10n.samplesDetail(model.sampleCount, model.resetCount)
                    : l10n.coldStartSamples),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.camera_viewfinder,
                    color: blue, size: 24),
                title: Text(l10n.scenePreference),
                subtitle: Text(l10n.scenePreferenceSubtitle),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _showSceneDetail(context, ref),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.clock, color: blue, size: 24),
                title: Text(l10n.lastUpdated),
                subtitle: Text(model.lastUpdated == null
                    ? '—'
                    : l10n.formatDateTime(model.lastUpdated!)),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.share, color: blue, size: 24),
                title: Text(l10n.exportPref),
                subtitle: Text(l10n.exportPrefSubtitle),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _exportPref(context, ref),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.arrow_counterclockwise,
                    color: Ios.red(b), size: 24),
                title: Text(l10n.resetPreferenceAction),
                subtitle: Text(l10n.resetPrefSubtitle),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _resetPref(context, ref),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: Text(l10n.privacyAndData),
            children: [
              CupertinoListTile(
                leading: Icon(CupertinoIcons.chart_bar, color: blue, size: 24),
                title: Text(l10n.helpImprove),
                subtitle: Text(l10n.helpImproveSubtitle),
                trailing: CupertinoSwitch(
                  value: settings.helpImprove,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).toggleHelpImprove(v),
                ),
              ),
              CupertinoListTile(
                leading: Icon(CupertinoIcons.shield, color: blue, size: 24),
                title: Text(l10n.confirmBeforeDelete),
                subtitle: Text(l10n.confirmBeforeDeleteSubtitle),
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
            header: Text(l10n.about),
            children: [
              CupertinoListTile(
                leading: Icon(CupertinoIcons.info, color: blue, size: 24),
                title: Text(l10n.aboutTitle),
                subtitle: Text(l10n.aboutSubtitle),
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
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l10n.sceneDetailTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  l10n.sceneDetailIntro,
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
                            l10n.sceneLabel(entry.key),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${l10n.samplesCount(entry.value.sampleCount)}'
                          '${entry.value.isTrained ? '' : l10n.coldStartShort}',
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
                  l10n.sceneGlobalNote,
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
            child: Text(l10n.close),
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
        text: context.l10n.exportPrefText,
      ));
    } catch (e) {
      if (context.mounted) {
        showIosToast(context, context.l10n.exportFailed(e));
      }
    }
  }

  Future<void> _resetPref(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.l10n.resetPrefDialogTitle),
        content: Text(context.l10n.resetPrefDialogContent),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.resetPreferenceAction),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      Haptics.warning();
      await ref.read(learningProvider).confirmReset();
      if (context.mounted) {
        showIosToast(context, context.l10n.preferenceResetToast, success: true);
      }
    }
  }
}
