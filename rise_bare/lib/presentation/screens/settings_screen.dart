import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/utils/i18n.dart';
import '../providers/locale_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          const _SettingsSection(
            title: 'General',
            children: [
              _LanguageSelector(),
              _ThemeSelector(),
            ],
          ),
          const _SettingsSection(
            title: 'Updates',
            children: [
              _AutoUpdateToggle(),
            ],
          ),
          const _SettingsSection(
            title: 'About',
            children: [
              _AboutTile(),
              _DonateTile(),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...children,
        const Divider(),
      ],
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, _) {
        return ListTile(
          leading: const Icon(Icons.language),
          title: const Text('Language'),
          subtitle: Text(AppLocales.supportedLanguages[localeProvider.locale.languageCode] ?? 'English'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            showModalBottomSheet(
              context: context,
              builder: (context) => ListView(
                shrinkWrap: true,
                children: AppLocales.supportedLocales.map((locale) {
                  return ListTile(
                    title: Text(AppLocales.supportedLanguages[locale.languageCode] ?? locale.languageCode),
                    trailing: localeProvider.locale.languageCode == locale.languageCode
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () {
                      localeProvider.setLocale(locale);
                      Navigator.of(context).pop();
                    },
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: const Text('Theme'),
      subtitle: const Text('System'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // TODO: Implement theme selector
      },
    );
  }
}

class _AutoUpdateToggle extends StatelessWidget {
  const _AutoUpdateToggle();

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.system_update_outlined),
      title: const Text('Auto-update scripts'),
      subtitle: const Text('Update scripts on startup and every 6 hours'),
      value: true,
      onChanged: (value) {
        // TODO: Implement toggle
      },
    );
  }
}

class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.info_outline),
      title: const Text('RISE Bare'),
      subtitle: const Text('Version 1.0.0'),
      onTap: () {
        showAboutDialog(
          context: context,
          applicationName: 'RISE Bare',
          applicationVersion: '1.0.0',
          applicationLegalese: '© 2024 RISE Bare. All rights reserved.',
        );
      },
    );
  }
}

class _DonateTile extends StatelessWidget {
  const _DonateTile();

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.favorite,
        color: Theme.of(context).colorScheme.error,
      ),
      title: const Text('Support RISE Development'),
      onTap: () {
        // TODO: Open donation link
      },
    );
  }
}
