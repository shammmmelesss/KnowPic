import 'dart:ui' show Locale;

import '../models/best_reason.dart';
import '../models/group_type.dart';
import '../models/scan_progress.dart';

/// 语言选项（写入设置的值即 [AppLanguage.code]）
enum AppLanguage {
  /// 跟随系统语言
  system,

  /// 简体中文
  zh,

  /// English
  en;

  String get code => name;

  /// 对应 Locale；跟随系统时返回 null（由 app.dart 按系统 locale 解析）
  Locale? get locale => switch (this) {
        AppLanguage.system => null,
        AppLanguage.zh => const Locale('zh'),
        AppLanguage.en => const Locale('en'),
      };

  static AppLanguage fromCode(String? code) {
    for (final l in AppLanguage.values) {
      if (l.code == code) return l;
    }
    return AppLanguage.system;
  }
}

/// 应用文案（自建轻量 l10n：不引入 flutter_localizations，
/// 全部界面文案集中在此，新增语言只需再实现一个子类。
abstract class AppStrings {
  const AppStrings();

  static const List<String> supportedLanguageCodes = ['zh', 'en'];

  static const List<Locale> supportedLocales = [Locale('zh'), Locale('en')];

  /// 按语言码取文案包；未知语言回落到中文（App 的主语言）
  static AppStrings of(Locale locale) {
    switch (locale.languageCode) {
      case 'en':
        return const StringsEn();
      default:
        return const StringsZh();
    }
  }

  static AppStrings ofCode(String? code) => of(Locale(code ?? 'zh'));

  /// 系统语言 → 支持的语言（不在支持列表内时用中文兜底）
  static Locale resolveSystem(Locale system) {
    if (system.languageCode == 'en') return const Locale('en');
    return const Locale('zh');
  }

  // ---- 通用 ----

  String get cancel;
  String get close;
  String get retry;
  String get delete;
  String get keep;
  String get backHome;

  // ---- 首页 ----

  String get appTitle;
  String get settings;
  String greeting(DateTime now);
  String get rescan;
  String get noScanRecord;
  String get photoUnit;
  String get groupUnit;
  String get quickEntries;
  String get recent30Days;
  String get scanning;
  String get startScan;
  String get permissionToast;
  String get readLibraryFailed;
  String get recentEmptyTitle;
  String get recentEmptySubtitle;
  String get statsTitle;
  String get statScanned;
  String get statGroups;
  String get statReclaimable;
  String get lastScanPrefix;
  String get quickGroups;
  String get quickTrash;
  String get quickReport;
  String get quickMemories;
  String get permissionTitle;
  String get permissionBodyLead;
  String get permissionBodyStrong;
  String get permissionBodyTail;
  String get permissionNote;
  String get grantAccess;
  String get openSystemSettings;

  // ---- 扫描页 ----

  String get scanTitle;
  String get scanIdleSubtitle;
  String get scanClusteringSubtitle;
  String get scanSavingSubtitle;
  String get analyzeTitle;
  String analyzePipeline(int current, int total);
  String scanDoneSummary(double seconds, int count);
  String get viewGroups;
  String get scanFailedTitle;
  String get scanFailedSubtitle;

  // ---- 相似组列表 ----

  String get groupsTitle;
  String get groupsEmptyTitle;
  String get groupsEmptySubtitle;
  String groupsSummary(int groupCount, String bytes);

  // ---- 相似组卡片 ----

  String groupSize(int count, String bytes);
  String reclaimableBytes(String bytes);
  String get aiBest;

  // ---- 相似组详情 ----

  String groupDetailTitle(GroupType type, int count);
  String keepSelected(int keep, int total);
  String estimatedFree(String bytes);
  String get noPhotos;
  String get keepAll;
  String cleanNow(String? bytes);
  String get groupCleaned;
  String get confirmCleanTitle;
  String confirmCleanContent(int count, String bytes);
  String get confirmClean;
  String get nothingDeletedBySystem;
  String get nothingDeletedByCloud;
  String cleanedCount(int count);
  String skippedByCloud(int count);
  String failedBySystem(int count);
  String freedAndRestorable(String bytes);
  String cleanFailed(Object err);
  String get resetPromptTitle;
  String get resetPromptContent;
  String get keepLearning;
  String get resetPreferenceAction;
  String get preferenceResetLearning;

  // ---- 记忆 ----

  String get memoriesTitle;
  String get blindBox;
  String get todayInHistory;
  String get noOldPhotosToast;
  String get scanFirstTitle;
  String get scanFirstSubtitle;
  String get openOldMoment;
  String get pickOne;
  String get pickAgain;
  String pickedTimes(int count);
  String get noHistoryTitle;
  String get noHistorySubtitle;

  // ---- 回收站 ----

  String get trashTitle;
  String get emptyTrashAction;
  String get trashEmptyTitle;
  String get trashEmptySubtitle;
  String get trashNotice;
  String restored(bool livePhoto);
  String get restoreFailed;
  String get permanentDeleteTitle;
  String get permanentDeleteContent;
  String get permanentDeleteAction;
  String get emptyTrashTitle;
  String get emptyTrashContent;
  String get trashCleared;
  String get livePhotoSuffix;
  String get expired;
  String remainingDays(int days);
  String photoSize(String bytes, bool livePhoto);

  // ---- 清理报告 ----

  String get reportTitle;
  String get reportEmptyTitle;
  String get reportEmptySubtitle;
  String freed(String bytes);
  String get reportDeleted;
  String get reportKept;
  String get reportGroups;
  String groupTypeBadge(GroupType type, int count);

  // ---- 设置页 ----

  String get photoPermission;
  String get privacyFooter;
  String get accessStatus;
  String get authorized;
  String get unauthorized;
  String get grantAction;
  String get prefModel;
  String get learnedSamples;
  String samplesDetail(int count, int resetCount);
  String get coldStartSamples;
  String get scenePreference;
  String get scenePreferenceSubtitle;
  String get lastUpdated;
  String get exportPref;
  String get exportPrefSubtitle;
  String get exportPrefText;
  String exportFailed(Object err);
  String get sceneDetailTitle;
  String get sceneDetailIntro;
  String samplesCount(int count);
  String get coldStartShort;
  String get sceneGlobalNote;
  String get privacyAndData;
  String get helpImprove;
  String get helpImproveSubtitle;
  String get confirmBeforeDelete;
  String get confirmBeforeDeleteSubtitle;
  String get about;
  String get aboutTitle;
  String get aboutSubtitle;
  String get resetPrefDialogTitle;
  String get resetPrefDialogContent;
  String get resetPrefSubtitle;
  String get preferenceResetToast;

  // ---- 语言设置 ----

  String get language;
  String languageName(AppLanguage lang);
  String languageFooter(String current);

  // ---- 动态文案（服务层只产出枚举，文案在此解析）----

  String groupType(GroupType type);
  String groupTypeShort(GroupType type);
  String bestReason(BestReason reason);
  String sceneLabel(String scene);
  String scanStatus(ScanPhase phase, {int current = 0, int total = 0});

  // ---- 数量与时间 ----

  String photoCount(int count);
  String groupCountLabel(int count);
  String formatDateTime(DateTime d);
  String formatDate(DateTime d);
  String formatMonthDayTime(DateTime d);
  String formatMonthDay(DateTime d);
  String yearLabel(int year);

  /// 两位补零的时:分
  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 简体中文
class StringsZh extends AppStrings {
  const StringsZh();

  @override
  String get cancel => '取消';
  @override
  String get close => '关闭';
  @override
  String get retry => '重试';
  @override
  String get delete => '删除';
  @override
  String get keep => '保留';
  @override
  String get backHome => '返回首页';

  @override
  String get appTitle => 'KnowPic';
  @override
  String get settings => '设置';
  @override
  String greeting(DateTime now) => switch (now.hour) {
      < 6 => '凌晨好 👋',
      < 12 => '上午好 👋',
      < 14 => '中午好 👋',
      < 18 => '下午好 👋',
      _ => '晚上好 👋',
    };
  @override
  String get rescan => '重新扫描';
  @override
  String get noScanRecord => '还没有扫描记录';
  @override
  String get photoUnit => '张';
  @override
  String get groupUnit => '组';
  @override
  String get quickEntries => '快捷入口';
  @override
  String get recent30Days => '最近 30 天';
  @override
  String get scanning => '扫描中…';
  @override
  String get startScan => '开始扫描';
  @override
  String get permissionToast => '未获得相册权限，可在系统设置中手动开启';
  @override
  String get readLibraryFailed => '读取相册失败';
  @override
  String get recentEmptyTitle => '最近 30 天暂无照片';
  @override
  String get recentEmptySubtitle => '点击右下角「开始扫描」，在后台整理全部照片';
  @override
  String get statsTitle => '相册空间概览';
  @override
  String get statScanned => '已扫描';
  @override
  String get statGroups => '相似组';
  @override
  String get statReclaimable => '可释放';
  @override
  String get lastScanPrefix => '上次扫描：';
  @override
  String get quickGroups => '相似组';
  @override
  String get quickTrash => '回收站';
  @override
  String get quickReport => '清理报告';
  @override
  String get quickMemories => '记忆';
  @override
  String get permissionTitle => '整理重复照片，需要一个相册权限';
  @override
  String get permissionBodyLead =>
      '为了帮您找到重复照片，我们需要读取相册。\n所有分析均在手机本地完成，';
  @override
  String get permissionBodyStrong => '绝不联网上传';
  @override
  String get permissionBodyTail => '。';
  @override
  String get permissionNote =>
      '您可以选择「部分照片」授权，App 会优雅降级；\n图片也不会离开您的设备。';
  @override
  String get grantAccess => '授权访问相册';
  @override
  String get openSystemSettings => '前往系统设置开启';

  @override
  String get scanTitle => '智能扫描';
  @override
  String get scanIdleSubtitle => '点击「开始扫描」即可整理相册';
  @override
  String get scanClusteringSubtitle => '按 dHash 感知哈希识别相似照片…';
  @override
  String get scanSavingSubtitle => '写入特征库与分组索引…';
  @override
  String get analyzeTitle => '正在提取特征';
  @override
  String analyzePipeline(int current, int total) =>
      '$current/$total · 流水线：缩略图 → dHash → 128 维特征 → 美学分';
  @override
  String scanDoneSummary(double seconds, int count) =>
      '耗时 ${seconds.toStringAsFixed(1)} 秒，分析 $count 张照片';
  @override
  String get viewGroups => '查看相似组';
  @override
  String get scanFailedTitle => '扫描未能完成';
  @override
  String get scanFailedSubtitle => '扫描过程中断，可重试或返回首页稍后再试';

  @override
  String get groupsTitle => '相似组';
  @override
  String get groupsEmptyTitle => '还没有相似组';
  @override
  String get groupsEmptySubtitle =>
      '回到首页点击「开始扫描」，自动识别连拍、截图与重复照片';
  @override
  String groupsSummary(int groupCount, String bytes) =>
      '共 $groupCount 组相似照片，一键清理可释放约 $bytes';

  @override
  String groupSize(int count, String bytes) => '$count 张 · $bytes';
  @override
  String reclaimableBytes(String bytes) => '可释放 $bytes';
  @override
  String get aiBest => 'AI 最佳';

  @override
  String groupDetailTitle(GroupType type, int count) =>
      '${groupType(type)}（$count 张）';
  @override
  String keepSelected(int keep, int total) => '已选保留 $keep/$total 张';
  @override
  String estimatedFree(String bytes) => '预计释放 $bytes';
  @override
  String get noPhotos => '暂无照片';
  @override
  String get keepAll => '全部保留';
  @override
  String cleanNow(String? bytes) =>
      bytes == null ? '一键清理' : '一键清理（$bytes）';
  @override
  String get groupCleaned => '该分组已清理';
  @override
  String get confirmCleanTitle => '确认清理？';
  @override
  String confirmCleanContent(int count, String bytes) =>
      '将删除 $count 张照片（释放约 $bytes）。\n\n已删除照片会进入回收站，保留 30 天，可随时还原。';
  @override
  String get confirmClean => '确认清理';
  @override
  String get nothingDeletedBySystem => '未删除任何照片（系统删除被取消或失败）';
  @override
  String get nothingDeletedByCloud => '未删除任何照片（云端照片尚未下载到本机）';
  @override
  String cleanedCount(int count) => '已清理 $count 张';
  @override
  String skippedByCloud(int count) => '，$count 张因云端未下载被跳过';
  @override
  String failedBySystem(int count) => '，$count 张系统删除失败';
  @override
  String freedAndRestorable(String bytes) => '已释放 $bytes，可在回收站还原';
  @override
  String cleanFailed(Object err) => '清理失败：$err';
  @override
  String get resetPromptTitle => '看起来推荐不太对？';
  @override
  String get resetPromptContent =>
      'AI 已经连续多次推荐了您不喜欢的照片。是否重置偏好模型，重新学习您的喜好？';
  @override
  String get keepLearning => '继续学习';
  @override
  String get resetPreferenceAction => '重置偏好';
  @override
  String get preferenceResetLearning => '偏好已重置，将重新学习您的喜好';

  @override
  String get memoriesTitle => '记忆';
  @override
  String get blindBox => '记忆盲盒';
  @override
  String get todayInHistory => '那年今日';
  @override
  String get noOldPhotosToast => '暂无可抽取的老照片（需要 90 天以上的照片）';
  @override
  String get scanFirstTitle => '先扫描相册';
  @override
  String get scanFirstSubtitle => '扫描完成后即可抽取记忆盲盒';
  @override
  String get openOldMoment => '随机翻开一段旧时光';
  @override
  String get pickOne => '抽取一张';
  @override
  String get pickAgain => '再来一个';
  @override
  String pickedTimes(int count) => '已抽取 $count 次';
  @override
  String get noHistoryTitle => '今天没有往年照片';
  @override
  String get noHistorySubtitle => '历史上的今天暂无照片，明天再来看看';

  @override
  String get trashTitle => '回收站';
  @override
  String get emptyTrashAction => '清空';
  @override
  String get trashEmptyTitle => '回收站是空的';
  @override
  String get trashEmptySubtitle => '清理的照片会在这里保留 30 天，可随时还原';
  @override
  String get trashNotice =>
      '已删除照片保留 30 天，过期将自动彻底删除；还原后照片将回到系统相册。';
  @override
  String restored(bool livePhoto) =>
      livePhoto ? '已还原（Live Photo 仅还原静态图）' : '已还原';
  @override
  String get restoreFailed => '还原失败，请重试';
  @override
  String get permanentDeleteTitle => '彻底删除？';
  @override
  String get permanentDeleteContent => '此操作不可恢复，照片将被永久删除。';
  @override
  String get permanentDeleteAction => '彻底删除';
  @override
  String get emptyTrashTitle => '清空回收站？';
  @override
  String get emptyTrashContent => '将彻底删除回收站中的所有照片，此操作不可恢复。';
  @override
  String get trashCleared => '回收站已清空';
  @override
  String get livePhotoSuffix => ' · Live';
  @override
  String get expired => '已过期';
  @override
  String remainingDays(int days) => '还剩 $days 天';
  @override
  String photoSize(String bytes, bool livePhoto) =>
      livePhoto ? '$bytes · Live' : bytes;

  @override
  String get reportTitle => '清理报告';
  @override
  String get reportEmptyTitle => '还没有清理记录';
  @override
  String get reportEmptySubtitle => '完成一次「一键清理」后，这里会展示释放的空间';
  @override
  String freed(String bytes) => '释放 $bytes';
  @override
  String get reportDeleted => '删除';
  @override
  String get reportKept => '保留';
  @override
  String get reportGroups => '处理组';
  @override
  String groupTypeBadge(GroupType type, int count) =>
      '${groupTypeShort(type)} × $count';

  @override
  String get photoPermission => '相册权限';
  @override
  String get privacyFooter =>
      '隐私承诺：所有分析均在手机本地完成，图片绝不联网上传；可随时在系统设置中改为「部分照片」访问。';
  @override
  String get accessStatus => '访问状态';
  @override
  String get authorized => '已授权';
  @override
  String get unauthorized => '未授权';
  @override
  String get grantAction => '去授权';
  @override
  String get prefModel => '个人偏好模型';
  @override
  String get learnedSamples => '已学习样本';
  @override
  String samplesDetail(int count, int resetCount) => resetCount == 0
      ? '$count 条 · 从未重置'
      : '$count 条 · 已重置 $resetCount 次';
  @override
  String get coldStartSamples => '尚无样本，冷启动中（纯客观评分）';
  @override
  String get scenePreference => '场景偏好';
  @override
  String get scenePreferenceSubtitle => '人像/风景/截图等分别独立学习';
  @override
  String get lastUpdated => '最近更新';
  @override
  String get exportPref => '导出偏好';
  @override
  String get exportPrefSubtitle => '加密偏好文件（几 KB），可自行备份迁移';
  @override
  String get exportPrefText => 'KnowPic 偏好模型导出（请妥善保管）';
  @override
  String exportFailed(Object err) => '导出失败：$err';
  @override
  String get sceneDetailTitle => '场景偏好详情';
  @override
  String get sceneDetailIntro => '每个场景独立学习您的审美（FTRL），互不干扰：';
  @override
  String samplesCount(int count) => '$count 条';
  @override
  String get coldStartShort => '（冷启动）';
  @override
  String get sceneGlobalNote => '全局模型汇总所有场景样本，供跨场景兜底。';
  @override
  String get privacyAndData => '隐私与数据';
  @override
  String get helpImprove => '帮助改进产品';
  @override
  String get helpImproveSubtitle => '仅上传脱敏统计（采纳率等），不含任何图片信息';
  @override
  String get confirmBeforeDelete => '清理前二次确认';
  @override
  String get confirmBeforeDeleteSubtitle => '默认开启，防误删';
  @override
  String get about => '关于';
  @override
  String get aboutTitle => 'KnowPic 智能相册整理助手';
  @override
  String get aboutSubtitle => '版本 1.0.0 · 全本地离线 · 隐私第一';
  @override
  String get resetPrefDialogTitle => '重置偏好模型？';
  @override
  String get resetPrefDialogContent =>
      '将清空已学习的个人偏好，恢复为纯客观评分排序。';
  @override
  String get resetPrefSubtitle => '清空所有场景的学习结果，退回客观排序';
  @override
  String get preferenceResetToast => '偏好已重置';

  @override
  String get language => '语言';
  @override
  String languageName(AppLanguage lang) => switch (lang) {
        AppLanguage.system => '跟随系统',
        AppLanguage.zh => '简体中文',
        AppLanguage.en => 'English',
      };
  @override
  String languageFooter(String current) => '当前显示语言：$current';

  @override
  String groupType(GroupType type) => switch (type) {
        GroupType.burst => '连拍组',
        GroupType.editHistory => '修图稿',
        GroupType.screenshot => '截图组',
        GroupType.duplicate => '重复照片',
        GroupType.longShot => '长图/全景',
        GroupType.mixed => '相似组',
      };
  @override
  String groupTypeShort(GroupType type) => switch (type) {
        GroupType.burst => '连拍',
        GroupType.editHistory => '修图稿',
        GroupType.screenshot => '截图',
        GroupType.duplicate => '重复',
        GroupType.longShot => '长图',
        GroupType.mixed => '相似',
      };
  @override
  String bestReason(BestReason reason) => switch (reason) {
        BestReason.onlyChoice => '唯一选择',
        BestReason.decisiveMoment => '决定性瞬间',
        BestReason.bestGroupExpression => '合影表情最佳',
        BestReason.sharpest => '最清晰',
        BestReason.bestExposure => '曝光最佳',
        BestReason.bestColor => '色彩最佳',
        BestReason.bestExpression => '表情最佳',
        BestReason.overallBest => '综合最佳',
      };
  @override
  String sceneLabel(String scene) => switch (scene) {
        'portrait' => '人像',
        'landscape' => '风景',
        'document' => '文档/截图',
        'food' => '美食',
        'other' => '其他',
        'all' => '全局',
        _ => scene,
      };
  @override
  String scanStatus(ScanPhase phase, {int current = 0, int total = 0}) =>
      switch (phase) {
        ScanPhase.reading =>
          current > 0 ? '正在读取相册（$current）…' : '正在读取相册…',
        ScanPhase.analyzing => total > 0
            ? '正在提取特征（$current/$total）…'
            : '正在提取特征…',
        ScanPhase.clustering => '正在聚类分组…',
        ScanPhase.saving => '正在保存…',
        ScanPhase.done => '扫描完成',
        ScanPhase.failed => '扫描失败',
        ScanPhase.idle => '准备就绪',
      };

  @override
  String photoCount(int count) => '$count 张';
  @override
  String groupCountLabel(int count) => '$count 组';
  @override
  String formatDateTime(DateTime d) =>
      '${d.year}年${d.month}月${d.day}日 ${_hm(d)}';
  @override
  String formatDate(DateTime d) => '${d.year}年${d.month}月${d.day}日';
  @override
  String formatMonthDayTime(DateTime d) => '${d.month}月${d.day}日 ${_hm(d)}';
  @override
  String formatMonthDay(DateTime d) => '${d.month}月${d.day}日';
  @override
  String yearLabel(int year) => '$year年';
}

/// English
class StringsEn extends AppStrings {
  const StringsEn();

  static const _months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _month(int m) => _months[(m - 1).clamp(0, 11).toInt()];

  @override
  String get cancel => 'Cancel';
  @override
  String get close => 'Close';
  @override
  String get retry => 'Retry';
  @override
  String get delete => 'Delete';
  @override
  String get keep => 'Keep';
  @override
  String get backHome => 'Back to Home';

  @override
  String get appTitle => 'KnowPic';
  @override
  String get settings => 'Settings';
  @override
  String greeting(DateTime now) => switch (now.hour) {
      < 12 => 'Good morning 👋',
      < 18 => 'Good afternoon 👋',
      _ => 'Good evening 👋',
    };
  @override
  String get rescan => 'Rescan';
  @override
  String get noScanRecord => 'No scans yet';
  @override
  String get photoUnit => 'photos';
  @override
  String get groupUnit => 'groups';
  @override
  String get quickEntries => 'Shortcuts';
  @override
  String get recent30Days => 'Last 30 Days';
  @override
  String get scanning => 'Scanning…';
  @override
  String get startScan => 'Start Scan';
  @override
  String get permissionToast =>
      'Photo access not granted. You can enable it in System Settings.';
  @override
  String get readLibraryFailed => 'Could not read your photo library';
  @override
  String get recentEmptyTitle => 'No photos in the last 30 days';
  @override
  String get recentEmptySubtitle =>
      'Tap “Start Scan” at the bottom right to organize everything in the background';
  @override
  String get statsTitle => 'Library Overview';
  @override
  String get statScanned => 'Scanned';
  @override
  String get statGroups => 'Groups';
  @override
  String get statReclaimable => 'Reclaimable';
  @override
  String get lastScanPrefix => 'Last scan: ';
  @override
  String get quickGroups => 'Duplicates';
  @override
  String get quickTrash => 'Trash';
  @override
  String get quickReport => 'Reports';
  @override
  String get quickMemories => 'Memories';
  @override
  String get permissionTitle => 'Photo access is needed to find duplicates';
  @override
  String get permissionBodyLead =>
      'To find duplicate photos we need to read your library.\nEverything is analyzed on-device — ';
  @override
  String get permissionBodyStrong => 'nothing is ever uploaded';
  @override
  String get permissionBodyTail => '.';
  @override
  String get permissionNote =>
      'You can grant access to “Selected Photos” only; the app degrades gracefully.\nYour photos never leave the device.';
  @override
  String get grantAccess => 'Allow Access to Photos';
  @override
  String get openSystemSettings => 'Open System Settings';

  @override
  String get scanTitle => 'Smart Scan';
  @override
  String get scanIdleSubtitle => 'Tap “Start Scan” to organize your library';
  @override
  String get scanClusteringSubtitle =>
      'Grouping similar photos with perceptual dHash…';
  @override
  String get scanSavingSubtitle => 'Writing feature store and group index…';
  @override
  String get analyzeTitle => 'Extracting features';
  @override
  String analyzePipeline(int current, int total) =>
      '$current/$total · pipeline: thumbnail → dHash → 128-D features → aesthetic score';
  @override
  String scanDoneSummary(double seconds, int count) =>
      'Analyzed $count photos in ${seconds.toStringAsFixed(1)}s';
  @override
  String get viewGroups => 'View Groups';
  @override
  String get scanFailedTitle => 'Scan did not finish';
  @override
  String get scanFailedSubtitle =>
      'The scan was interrupted. Retry now or come back later.';

  @override
  String get groupsTitle => 'Similar Groups';
  @override
  String get groupsEmptyTitle => 'No groups yet';
  @override
  String get groupsEmptySubtitle =>
      'Tap “Start Scan” on the home screen to detect bursts, screenshots and duplicates';
  @override
  String groupsSummary(int groupCount, String bytes) =>
      '$groupCount groups of similar photos — a one-tap cleanup frees about $bytes';

  @override
  String groupSize(int count, String bytes) => '$count photos · $bytes';
  @override
  String reclaimableBytes(String bytes) => 'Free $bytes';
  @override
  String get aiBest => 'AI Best';

  @override
  String groupDetailTitle(GroupType type, int count) =>
      '${groupType(type)} ($count)';
  @override
  String keepSelected(int keep, int total) => 'Keeping $keep of $total';
  @override
  String estimatedFree(String bytes) => 'Frees about $bytes';
  @override
  String get noPhotos => 'No photos';
  @override
  String get keepAll => 'Keep All';
  @override
  String cleanNow(String? bytes) => bytes == null ? 'Clean Up' : 'Clean Up ($bytes)';
  @override
  String get groupCleaned => 'This group is already cleaned up';
  @override
  String get confirmCleanTitle => 'Confirm cleanup?';
  @override
  String confirmCleanContent(int count, String bytes) =>
      '$count photos will be deleted (freeing about $bytes).\n\nDeleted photos go to Trash for 30 days and can be restored anytime.';
  @override
  String get confirmClean => 'Clean Up';
  @override
  String get nothingDeletedBySystem =>
      'No photos were deleted (system deletion cancelled or failed)';
  @override
  String get nothingDeletedByCloud =>
      'No photos were deleted (iCloud photos are not downloaded yet)';
  @override
  String cleanedCount(int count) => 'Cleaned $count photos';
  @override
  String skippedByCloud(int count) =>
      ', $count skipped because they are not downloaded';
  @override
  String failedBySystem(int count) => ', $count failed to delete';
  @override
  String freedAndRestorable(String bytes) =>
      'Freed $bytes — restorable from Trash';
  @override
  String cleanFailed(Object err) => 'Cleanup failed: $err';
  @override
  String get resetPromptTitle => 'Recommendations feel off?';
  @override
  String get resetPromptContent =>
      'The AI has been recommending photos you don’t like several times in a row. Reset the preference model and start learning again?';
  @override
  String get keepLearning => 'Keep Learning';
  @override
  String get resetPreferenceAction => 'Reset';
  @override
  String get preferenceResetLearning =>
      'Preferences reset — learning your taste again';

  @override
  String get memoriesTitle => 'Memories';
  @override
  String get blindBox => 'Blind Box';
  @override
  String get todayInHistory => 'On This Day';
  @override
  String get noOldPhotosToast =>
      'No old photos to draw yet (photos older than 90 days are needed)';
  @override
  String get scanFirstTitle => 'Scan your library first';
  @override
  String get scanFirstSubtitle => 'You can draw a memory blind box after scanning';
  @override
  String get openOldMoment => 'Revisit a random old moment';
  @override
  String get pickOne => 'Draw One';
  @override
  String get pickAgain => 'Another One';
  @override
  String pickedTimes(int count) => 'Drawn $count times';
  @override
  String get noHistoryTitle => 'Nothing from past years today';
  @override
  String get noHistorySubtitle =>
      'No photos from this day in past years — come back tomorrow';

  @override
  String get trashTitle => 'Trash';
  @override
  String get emptyTrashAction => 'Empty';
  @override
  String get trashEmptyTitle => 'Trash is empty';
  @override
  String get trashEmptySubtitle =>
      'Cleaned photos stay here for 30 days and can be restored anytime';
  @override
  String get trashNotice =>
      'Deleted photos are kept for 30 days, then removed permanently. Restored photos return to your system library.';
  @override
  String restored(bool livePhoto) =>
      livePhoto ? 'Restored (Live Photo restored as a still image)' : 'Restored';
  @override
  String get restoreFailed => 'Restore failed, please try again';
  @override
  String get permanentDeleteTitle => 'Delete permanently?';
  @override
  String get permanentDeleteContent =>
      'This cannot be undone — the photo will be deleted forever.';
  @override
  String get permanentDeleteAction => 'Delete';
  @override
  String get emptyTrashTitle => 'Empty Trash?';
  @override
  String get emptyTrashContent =>
      'All photos in Trash will be deleted permanently. This cannot be undone.';
  @override
  String get trashCleared => 'Trash emptied';
  @override
  String get livePhotoSuffix => ' · Live';
  @override
  String get expired => 'Expired';
  @override
  String remainingDays(int days) => '$days days left';
  @override
  String photoSize(String bytes, bool livePhoto) =>
      livePhoto ? '$bytes · Live' : bytes;

  @override
  String get reportTitle => 'Cleanup Report';
  @override
  String get reportEmptyTitle => 'No cleanups yet';
  @override
  String get reportEmptySubtitle =>
      'After a one-tap cleanup, the freed space shows up here';
  @override
  String freed(String bytes) => 'Freed $bytes';
  @override
  String get reportDeleted => 'Deleted';
  @override
  String get reportKept => 'Kept';
  @override
  String get reportGroups => 'Groups';
  @override
  String groupTypeBadge(GroupType type, int count) =>
      '${groupTypeShort(type)} × $count';

  @override
  String get photoPermission => 'Photo Access';
  @override
  String get privacyFooter =>
      'Privacy promise: everything is analyzed on-device and no photo is ever uploaded. You can switch to “Selected Photos” in System Settings at any time.';
  @override
  String get accessStatus => 'Access Status';
  @override
  String get authorized => 'Granted';
  @override
  String get unauthorized => 'Not Granted';
  @override
  String get grantAction => 'Grant';
  @override
  String get prefModel => 'Preference Model';
  @override
  String get learnedSamples => 'Learned Samples';
  @override
  String samplesDetail(int count, int resetCount) => resetCount == 0
      ? '$count · never reset'
      : '$count · reset $resetCount times';
  @override
  String get coldStartSamples =>
      'No samples yet — cold start (objective ranking only)';
  @override
  String get scenePreference => 'Scene Preferences';
  @override
  String get scenePreferenceSubtitle =>
      'Portraits, landscapes, screenshots and more are learned separately';
  @override
  String get lastUpdated => 'Last Updated';
  @override
  String get exportPref => 'Export Preferences';
  @override
  String get exportPrefSubtitle =>
      'Encrypted preference file (a few KB) for backup or migration';
  @override
  String get exportPrefText => 'KnowPic preference model export (keep it safe)';
  @override
  String exportFailed(Object err) => 'Export failed: $err';
  @override
  String get sceneDetailTitle => 'Scene Preference Details';
  @override
  String get sceneDetailIntro =>
      'Each scene learns your taste independently (FTRL):';
  @override
  String samplesCount(int count) => '$count';
  @override
  String get coldStartShort => ' (cold start)';
  @override
  String get sceneGlobalNote =>
      'The global model aggregates every scene as a cross-scene fallback.';
  @override
  String get privacyAndData => 'Privacy & Data';
  @override
  String get helpImprove => 'Help Improve';
  @override
  String get helpImproveSubtitle =>
      'Only anonymized statistics (e.g. acceptance rate) are uploaded, never any photo data';
  @override
  String get confirmBeforeDelete => 'Confirm Before Cleanup';
  @override
  String get confirmBeforeDeleteSubtitle =>
      'On by default, to prevent accidental deletion';
  @override
  String get about => 'About';
  @override
  String get aboutTitle => 'KnowPic — Smart Photo Organizer';
  @override
  String get aboutSubtitle =>
      'Version 1.0.0 · Fully offline · Privacy first';
  @override
  String get resetPrefDialogTitle => 'Reset preference model?';
  @override
  String get resetPrefDialogContent =>
      'This clears everything learned about your taste and falls back to objective ranking.';
  @override
  String get resetPrefSubtitle =>
      'Clear every scene’s learned results and fall back to objective ranking';
  @override
  String get preferenceResetToast => 'Preferences reset';

  @override
  String get language => 'Language';
  @override
  String languageName(AppLanguage lang) => switch (lang) {
        AppLanguage.system => 'Follow System',
        AppLanguage.zh => '简体中文',
        AppLanguage.en => 'English',
      };
  @override
  String languageFooter(String current) => 'Currently displaying: $current';

  @override
  String groupType(GroupType type) => switch (type) {
        GroupType.burst => 'Burst',
        GroupType.editHistory => 'Edited Versions',
        GroupType.screenshot => 'Screenshots',
        GroupType.duplicate => 'Duplicates',
        GroupType.longShot => 'Long / Panorama',
        GroupType.mixed => 'Similar',
      };
  @override
  String groupTypeShort(GroupType type) => switch (type) {
        GroupType.burst => 'Burst',
        GroupType.editHistory => 'Edited',
        GroupType.screenshot => 'Screenshot',
        GroupType.duplicate => 'Duplicate',
        GroupType.longShot => 'Long',
        GroupType.mixed => 'Similar',
      };
  @override
  String bestReason(BestReason reason) => switch (reason) {
        BestReason.onlyChoice => 'Only Option',
        BestReason.decisiveMoment => 'Decisive Moment',
        BestReason.bestGroupExpression => 'Best Group Expression',
        BestReason.sharpest => 'Sharpest',
        BestReason.bestExposure => 'Best Exposure',
        BestReason.bestColor => 'Best Color',
        BestReason.bestExpression => 'Best Expression',
        BestReason.overallBest => 'Best Overall',
      };
  @override
  String sceneLabel(String scene) => switch (scene) {
        'portrait' => 'Portrait',
        'landscape' => 'Landscape',
        'document' => 'Document',
        'food' => 'Food',
        'other' => 'Other',
        'all' => 'Overall',
        _ => scene,
      };
  @override
  String scanStatus(ScanPhase phase, {int current = 0, int total = 0}) =>
      switch (phase) {
        ScanPhase.reading =>
          current > 0 ? 'Reading library ($current)…' : 'Reading library…',
        ScanPhase.analyzing => total > 0
            ? 'Extracting features ($current/$total)…'
            : 'Extracting features…',
        ScanPhase.clustering => 'Grouping similar photos…',
        ScanPhase.saving => 'Saving…',
        ScanPhase.done => 'Scan complete',
        ScanPhase.failed => 'Scan failed',
        ScanPhase.idle => 'Ready',
      };

  @override
  String photoCount(int count) => count == 1 ? '1 photo' : '$count photos';
  @override
  String groupCountLabel(int count) => count == 1 ? '1 group' : '$count groups';
  @override
  String formatDateTime(DateTime d) =>
      '${_month(d.month)} ${d.day}, ${d.year} ${_hm(d)}';
  @override
  String formatDate(DateTime d) => '${_month(d.month)} ${d.day}, ${d.year}';
  @override
  String formatMonthDayTime(DateTime d) => '${_month(d.month)} ${d.day} ${_hm(d)}';
  @override
  String formatMonthDay(DateTime d) => '${_month(d.month)} ${d.day}';
  @override
  String yearLabel(int year) => '$year';
}
