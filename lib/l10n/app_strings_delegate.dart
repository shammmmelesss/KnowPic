import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app_strings.dart';

/// 将 [AppStrings] 接入 Flutter 的 Localizations 体系：
/// 语言切换时所有 `context.l10n` 处会自动重建。
class AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppStrings.supportedLanguageCodes.contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(AppStrings.of(locale));

  @override
  bool shouldReload(covariant LocalizationsDelegate<AppStrings> old) => false;
}

/// `context.l10n.xxx` 取当前语言的文案
extension AppL10n on BuildContext {
  AppStrings get l10n => Localizations.of<AppStrings>(this, AppStrings)!;
}
