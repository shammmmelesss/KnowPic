import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:knowpic/l10n/app_strings.dart';
import 'package:knowpic/l10n/app_strings_delegate.dart';
import 'package:knowpic/services/app_settings.dart';

Widget _app(Locale locale) => MaterialApp(
      locale: locale,
      supportedLocales: AppStrings.supportedLocales,
      localizationsDelegates: const [
        AppStringsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: Builder(builder: (ctx) => Text(ctx.l10n.settings)),
    );

void main() {
  testWidgets('跟随 locale 切换中英文文案', (tester) async {
    await tester.pumpWidget(_app(const Locale('zh')));
    expect(find.text('设置'), findsOneWidget);

    await tester.pumpWidget(_app(const Locale('en')));
    expect(find.text('Settings'), findsOneWidget);
  });

  test('不支持的系统语言回落到中文', () {
    expect(AppStrings.resolveSystem(const Locale('ja')), const Locale('zh'));
    expect(AppStrings.resolveSystem(const Locale('en')), const Locale('en'));
  });

  test('语言设置写入并读回', () async {
    final dir = await Directory.systemTemp.createTemp('knowpic_l10n_test');
    await Directory('${dir.path}/knowpic').create(recursive: true);
    final settings = AppSettings()..languageMode = AppLanguage.en.code;
    await settings.save(dir);
    final loaded = await AppSettings.load(dir);
    expect(loaded.languageMode, 'en');

    // 未设置过语言时默认跟随系统
    final dir2 = await Directory.systemTemp.createTemp('knowpic_l10n_test');
    expect((await AppSettings.load(dir2)).languageMode, 'system');
  });
}
