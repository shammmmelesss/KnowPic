import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/ios_design.dart';
import 'providers/providers.dart';
import 'screens/home_screen.dart';

/// 应用根组件（iOS 人机界面指南风格）
class KnowPicApp extends ConsumerStatefulWidget {
  const KnowPicApp({super.key});

  @override
  ConsumerState<KnowPicApp> createState() => _KnowPicAppState();
}

class _KnowPicAppState extends ConsumerState<KnowPicApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 用户可能刚去系统设置改了相册权限再切回来，回前台必须重新核对，
    // 否则界面会一直停在「未授权」，看起来像设置没生效
    if (state == AppLifecycleState.resumed) {
      ref.read(permissionControllerProvider.notifier).recheck();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KnowPic',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }

  ThemeData _theme(Brightness b) {
    final blue = Ios.blue(b);
    final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: b)
        .copyWith(
      primary: blue,
      onPrimary: Colors.white,
      secondary: Ios.indigo(b),
      tertiary: Ios.orange(b),
      error: Ios.red(b),
      onError: Colors.white,
      surface: Ios.card(b),
      onSurface: Ios.label(b),
      onSurfaceVariant: Ios.secondaryLabel(b),
      surfaceContainerHighest: Ios.fill(b),
      outlineVariant: Ios.separator(b),
      primaryContainer: blue.withValues(alpha: 0.14),
      onPrimaryContainer: blue,
      secondaryContainer: Ios.fill(b),
      onSecondaryContainer: Ios.label(b),
      tertiaryContainer: Ios.orange(b).withValues(alpha: 0.16),
      onTertiaryContainer: Ios.orange(b),
      errorContainer: Ios.red(b).withValues(alpha: 0.14),
      onErrorContainer: Ios.red(b),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: b,
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: Ios.bg(b),
      textTheme: Ios.textTheme(b),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Ios.label(b).withValues(alpha: 0.05),
      iconTheme: IconThemeData(color: blue),
      dividerTheme: DividerThemeData(color: Ios.separator(b), thickness: 0.5),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: blue,
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.41,
          color: Ios.label(b),
        ),
        iconTheme: IconThemeData(color: blue),
        actionsIconTheme: IconThemeData(color: blue),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
