import 'package:flutter/material.dart';
import '../../core/utils/i18n.dart';

class LocaleProvider extends ChangeNotifier {
  Locale _locale = const Locale('en');

  Locale get locale => _locale;

  void setLocale(Locale locale) {
    if (!AppLocales.supportedLocales.contains(locale)) return;
    _locale = locale;
    notifyListeners();
  }

  void setLocaleByCode(String code) {
    setLocale(Locale(code));
  }
}
