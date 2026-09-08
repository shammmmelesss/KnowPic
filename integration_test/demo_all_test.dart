import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:knowpic/main.dart' as app;
import 'package:knowpic/screens/groups_screen.dart';
import 'package:knowpic/screens/home_screen.dart';
import 'package:knowpic/screens/scan_screen.dart';

/// 全功能演示流程（integration_test 版）：
/// 首页 → 相似组 → 组详情（AI 最佳/轮播）→ 清理报告 → 记忆（盲盒/那年今日）
/// → 设置（场景偏好）→ 回收站 → 一键清理（真实删除，系统可能弹删除确认需人工点"允许"）→ 回收站复查。
/// 运行：`flutter test integration_test/demo_all_test.dart -d <simulator>`
/// 同步用 `xcrun simctl io booted screenshot` 抓取实时画面。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  late final WidgetTester tester;

  Future<void> pause(int ms) async {
    await Future.delayed(Duration(milliseconds: ms));
    await tester.pump();
  }

  Future<void> waitTap(Finder finder, {int settleMs = 1800}) async {
    await tester.tap(finder, warnIfMissed: false);
    await pause(settleMs);
  }

  testWidgets('KnowPic 全功能演示', (rawTester) async {
    tester = rawTester;
    await app.main();

    // 轮询等待首页就绪（权限异步恢复后快捷入口才出现，最多约 20 秒）
    var ready = false;
    for (var i = 0; i < 40 && !ready; i++) {
      await tester.pump(const Duration(milliseconds: 500));
      ready = find.byKey(const ValueKey('qa_相似组')).evaluate().isNotEmpty;
      if (!ready) await Future.delayed(const Duration(milliseconds: 500));
    }
    expect(ready, isTrue, reason: '首页快捷入口未在预期时间内出现');
    await pause(1000);

    // 1. 相似组列表
    await waitTap(find.byKey(const ValueKey('qa_相似组')));
    expect(find.byType(GroupsScreen), findsOneWidget);
    await pause(1200);

    // 2. 组详情：AI 最佳徽章 + 推荐理由（第一组）
    await waitTap(find.byKey(const ValueKey('group_card_0')));
    await pause(1500);

    // 3. 轮播左滑（停留 >1.5s 触发 viewLong 隐式正样本）
    await tester.drag(find.byType(PageView).first, const Offset(-320, 0));
    await tester.pump();
    await pause(1800);

    // 4. 返回列表 → 返回首页
    await waitTap(find.byType(BackButton));
    await pause(800);
    await waitTap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(HomeScreen), findsOneWidget);

    // 5. 清理报告
    await waitTap(find.byKey(const ValueKey('qa_清理报告')));
    await pause(1500);
    await waitTap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 6. 记忆：盲盒 → 那年今日
    await waitTap(find.byKey(const ValueKey('qa_记忆')));
    await pause(1500);
    await waitTap(find.text('那年今日'));
    await pause(1200);
    await waitTap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 7. 设置 → 场景偏好详情
    await waitTap(find.byTooltip('设置'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await waitTap(find.text('场景偏好'));
    await pause(1200);
    await waitTap(find.text('关闭'));
    await pause(600);
    await waitTap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    expect(find.byType(HomeScreen), findsOneWidget);

    // 8. 回收站（清理前）
    await waitTap(find.byKey(const ValueKey('qa_回收站')));
    await pause(1500);
    await waitTap(find.byType(BackButton));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 9. 一键清理演示（真实删除：系统若弹"允许删除照片"需人工点击允许）
    await waitTap(find.byKey(const ValueKey('qa_相似组')));
    await pause(1500);
    await waitTap(find.byKey(const ValueKey('group_card_0')));
    await pause(1500);
    await waitTap(find.textContaining('一键清理'));
    await pause(1200); // 确认弹窗
    await waitTap(find.text('确认清理'));
    await pause(30000); // 等待软删除 / 系统确认（人工点"允许"）/ snackbar / 自动返回

    // 10. 回收站复查（应含刚清理的照片）
    await waitTap(find.byType(BackButton), settleMs: 500);
    await pause(500);
    await waitTap(find.byType(BackButton), settleMs: 500);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await waitTap(find.byKey(const ValueKey('qa_回收站')));
    await pause(2000);

    // 收尾：截图窗口 + 结束标记
    await pause(4000);
    expect(find.byType(ScanScreen), findsNothing);
    stdout.writeln('[demo-all] DONE');
  });
}
