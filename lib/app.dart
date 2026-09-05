import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

/// 应用根组件（iOS 风格 Material 3）
class KnowPicApp extends StatelessWidget {
  const KnowPicApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3D5AFE);
    return MaterialApp(
      title: 'KnowPic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
