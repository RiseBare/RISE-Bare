import 'package:flutter/material.dart';

class AppLocales {
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
    'th': 'ไทย',
    'pt': 'Português',
    'ru': 'Русский',
  };

  static const List<Locale> supportedLocales = [
    Locale('en'),
    Locale('fr'),
    Locale('de'),
    Locale('es'),
    Locale('zh'),
    Locale('ja'),
    Locale('ko'),
    Locale('th'),
    Locale('pt'),
    Locale('ru'),
  ];
}

class AppLocalizationsDelegate extends LocalizationsDelegate<Map<String, String>> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return AppLocales.supportedLanguages.containsKey(locale.languageCode);
  }

  @override
  Future<Map<String, String>> load(Locale locale) async {
    // Return embedded fallback strings - Phase 2 will load from assets
    return _getFallbackStrings(locale.languageCode);
  }

  Map<String, String> _getFallbackStrings(String lang) {
    // Embedded fallback - English for Phase 1
    return const {
      'app.title': 'RISE Bare',
      'menu.file': 'File',
      'menu.addServer': 'Add Server',
      'menu.settings': 'Settings',
      'menu.exit': 'Exit',
      'server.list': 'Servers',
      'server.noServers': 'No servers configured. Click Add Server to begin.',
      'tab.firewall': 'Firewall',
      'tab.docker': 'Docker',
      'tab.updates': 'Updates',
      'tab.health': 'Health',
      'tab.security': 'Security',
      'status.connecting': 'Connecting...',
      'status.connected': 'Connected',
      'status.disconnected': 'Disconnected',
    };
  }

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
