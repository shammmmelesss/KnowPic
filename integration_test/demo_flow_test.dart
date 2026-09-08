import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:knowpic/main.dart' as app;
import 'package:knowpic/screens/scan_screen.dart';
import 'package:knowpic/widgets/group_card.dart';

/// 端到端演示流程：启动 → 授权兜底 → 扫描 → 查看相似组 → 组详情。
/// 运行：`flutter test integration_test/demo_flow_test.dart -d <simulator>`
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('演示：扫描 → 分组 → 详情', (tester) async {
    await app.main();
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 权限兜底：若授权卡片仍在（OS 未预授权），点击授权
    final grant = find.text('授权访问相册');
    if (grant.evaluate().isNotEmpty) {
      await tester.tap(grant);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // 首页 → 开始扫描
    expect(find.text('开始扫描'), findsOneWidget);
    await Future.delayed(const Duration(seconds: 4)); // 截图窗口：首页
    await tester.tap(find.text('开始扫描'));
    await tester.pump(const Duration(seconds: 1));

    // 等待扫描完成（最多 150 秒）
    final deadline = DateTime.now().add(const Duration(seconds: 150));
    var done = false;
    while (!done && DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(seconds: 1));
      done = find.text('扫描完成').evaluate().isNotEmpty;
    }
    expect(done, isTrue, reason: '扫描应在 150 秒内完成');
    await Future.delayed(const Duration(seconds: 6)); // 截图窗口：扫描完成

    // 查看相似组列表
    await tester.tap(find.text('查看相似组'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await Future.delayed(const Duration(seconds: 6)); // 截图窗口：分组列表

    // 打开第一个相似组详情（AI 推荐徽章）
    expect(find.byType(GroupCard), findsWidgets);
    await tester.tap(find.byType(GroupCard).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await Future.delayed(const Duration(seconds: 12)); // 截图窗口：组详情

    expect(find.byType(ScanScreen), findsNothing);
  });
}
