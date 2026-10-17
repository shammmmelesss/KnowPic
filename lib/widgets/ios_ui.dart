import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/haptics.dart';
import '../core/ios_design.dart';

/// 毛玻璃栏背景（HIG Materials：系统栏使用模糊材质）
Widget frostedBar(BuildContext context, {double alpha = 0.7}) {
  final cs = Theme.of(context).colorScheme;
  return ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(color: cs.surface.withValues(alpha: alpha)),
    ),
  );
}

/// iOS 风格应用栏：居中标题 + 毛玻璃
PreferredSizeWidget frostedAppBar(
  BuildContext context, {
  String? title,
  List<Widget> actions = const [],
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    title: title == null ? null : Text(title),
    actions: actions,
    bottom: bottom,
    centerTitle: true,
    elevation: 0,
    scrolledUnderElevation: 0,
    backgroundColor: Colors.transparent,
    flexibleSpace: frostedBar(context),
  );
}

/// 单行毛玻璃标题栏：标题与操作按钮同处一行。
/// 相比 SliverAppBar.large 去掉了大标题那一整块留白，同时保留 iOS 模糊材质。
/// 颜色/字重之外的部分由 appBarTheme 兜底（暗色模式仍跟随主题）。
SliverAppBar frostedSliverAppBar(
  BuildContext context, {
  required String title,
  List<Widget> actions = const [],
  Widget? leading,
  bool centerTitle = false,
  bool pinned = false,
  double toolbarHeight = 56,
}) {
  return SliverAppBar(
    leading: leading,
    title: Text(
      title,
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
    ),
    toolbarHeight: toolbarHeight,
    titleSpacing: 20,
    centerTitle: centerTitle,
    pinned: pinned,
    backgroundColor: Colors.transparent,
    flexibleSpace: frostedBar(context),
    actions: actions,
  );
}

/// 底部浮层提示（iOS 深色胶囊样式，替代 Material SnackBar）
void showIosToast(
  BuildContext context,
  String message, {
  bool success = false,
}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (success) ...[
            Icon(
              CupertinoIcons.check_mark_circled,
              color: Ios.green(Theme.of(context).brightness),
              size: 18,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      backgroundColor:
          dark ? const Color(0xF02C2C2E) : const Color(0xF01C1C1E),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const StadiumBorder(),
      margin: const EdgeInsets.only(left: 24, right: 24, bottom: 16),
      duration: const Duration(seconds: 2),
    ));
  if (success) {
    Haptics.success();
  } else {
    Haptics.tap();
  }
}

/// 按压缩放 + 触感反馈（iOS 按压态）
class IosPressable extends StatefulWidget {
  const IosPressable({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.96,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<IosPressable> createState() => _IosPressableState();
}

class _IosPressableState extends State<IosPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    // 禁用时不套手势：否则 onTapDown/Up 照旧触发，元素会"按得动"却毫无响应
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: () {
        Haptics.tap();
        widget.onTap!();
      },
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// iOS 分组背景上的卡片
class IosCard extends StatelessWidget {
  const IosCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.margin,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final b = Theme.of(context).brightness;
    final content = Padding(padding: padding, child: child);
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: color ?? Ios.card(b),
        borderRadius: BorderRadius.circular(Ios.radiusCard),
      ),
      child: onTap == null ? content : IosPressable(onTap: onTap, child: content),
    );
  }
}

/// 胶囊徽章
class IosBadge extends StatelessWidget {
  const IosBadge({
    super.key,
    required this.label,
    required this.color,
    required this.fg,
    this.icon,
    this.fontSize = 11,
  });

  final String label;
  final Color color;
  final Color fg;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 3, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
