import 'dart:io';

import 'package:flutter_driver/flutter_driver.dart';

/// KnowPic 演示全流程驱动脚本：
/// 首页 → 相似组 → 组详情（AI 最佳/轮播）→ 一键清理 → 清理报告 →
/// 记忆盲盒/那年今日 → 设置（场景偏好）→ 回收站。每步截图。
/// 运行：flutter drive --driver=test_driver/demo_test.dart --target=test_driver/app.dart
Future<void> main() async {
  final driver = await FlutterDriver.connect();
  await driver.waitUntilFirstFrameRasterized();

  var shotIdx = 0;
  Future<void> shot(String name) async {
    try {
      final data = await driver.screenshot();
      shotIdx++;
      final f = File(
          '/tmp/knowpic_shots3/demo_${shotIdx.toString().padLeft(2, '0')}_$name.png');
      await f.writeAsBytes(data);
      stdout.writeln('[shot] $name -> ${f.path}');
    } catch (e) {
      stdout.writeln('[shot-fail] $name: $e');
    }
  }

  Future<void> sleep(int ms) => Future.delayed(Duration(milliseconds: ms));

  /// 容错步骤：失败不中断后续演示
  Future<void> step(String name, Future<void> Function() body) async {
    try {
      await body();
      stdout.writeln('[step-ok] $name');
    } catch (e) {
      stdout.writeln('[step-fail] $name: $e');
    }
  }

  try {
    await sleep(3000); // 等冷启动权限恢复 + 首页数据加载
    await shot('home');

    // 1. 相似组列表
    await step('打开相似组', () async {
      await driver.tap(find.byValueKey('qa_相似组'));
      await sleep(1500);
    });
    await shot('groups');

    // 2. 第一组详情：AI 最佳徽章 + 推荐理由
    await step('打开组详情', () async {
      await driver.tap(find.byValueKey('group_card_0'));
      await sleep(2000);
    });
    await shot('detail_best');

    // 3. 左滑轮播（停留 >1.5s 触发 viewLong 隐式正样本）
    await step('轮播左滑', () async {
      await driver.scroll(find.byType('PageView'), -300, 0,
          const Duration(milliseconds: 400));
      await sleep(1800);
    });
    await shot('detail_second');

    // 4. 一键清理（若系统弹出删除确认，需人工点"允许"）
    await step('一键清理', () async {
      await driver.tap(find.byType('FilledButton'));
      await sleep(1000);
      await shot('confirm_dialog');
      await driver.tap(find.text('确认清理'));
      await sleep(9000); // 等软删除 + 系统确认（如有）+ 自动返回
    });
    await shot('after_clean');

    // 5. 返回首页
    await step('返回首页', () async {
      await driver.tap(find.pageBack());
      await sleep(1000);
      await driver.tap(find.pageBack());
      await sleep(1000);
    });

    // 6. 清理报告
    await step('打开清理报告', () async {
      await driver.tap(find.byValueKey('qa_清理报告'));
      await sleep(1500);
    });
    await shot('report');
    await step('关闭清理报告', () async {
      await driver.tap(find.pageBack());
      await sleep(1000);
    });

    // 7. 记忆：盲盒 + 那年今日
    await step('打开记忆', () async {
      await driver.tap(find.byValueKey('qa_记忆'));
      await sleep(1500);
    });
    await shot('memories_blindbox');
    await step('切换那年今日', () async {
      await driver.tap(find.text('那年今日'));
      await sleep(1200);
    });
    await shot('memories_today');
    await step('关闭记忆', () async {
      await driver.tap(find.pageBack());
      await sleep(1000);
    });

    // 8. 设置 + 场景偏好详情
    await step('打开设置', () async {
      await driver.tap(find.byTooltip('设置'));
      await sleep(1500);
    });
    await shot('settings');
    await step('打开场景偏好详情', () async {
      await driver.tap(find.text('场景偏好'));
      await sleep(1000);
    });
    await shot('scene_detail');
    await step('关闭场景偏好详情', () async {
      await driver.tap(find.text('关闭'));
      await sleep(600);
      await driver.tap(find.pageBack());
      await sleep(1000);
    });

    // 9. 回收站（含刚清理的照片，可还原）
    await step('打开回收站', () async {
      await driver.tap(find.byValueKey('qa_回收站'));
      await sleep(1500);
    });
    await shot('trash');

    stdout.writeln('[done] 演示流程结束，共 $shotIdx 张截图');
  } catch (e) {
    stdout.writeln('[fatal] $e');
  } finally {
    await driver.close();
  }
}
