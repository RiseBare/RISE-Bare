import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'cache_manager.dart';

/// Cache for i18n files with fallback support
class I18nCache {
  late final Directory _i18nDir;
  static const List<String> supportedLanguages = [
    'en', 'fr', 'de', 'es', 'zh', 'ja', 'ko', 'th', 'pt', 'ru'
  ];

  /// Fallback language
  static const String fallbackLanguage = 'en';

  I18nCache(Directory baseDir) {
    _i18nDir = Directory('${baseDir.path}/i18n');
  }

  /// Ensure i18n directory exists
  Future<void> _ensureI18nDir() async {
    if (!await _i18nDir.exists()) {
      await _i18nDir.create(recursive: true);
    }
  }

  /// Get the i18n version manifest - prefer local, fallback to GitHub
  Future<Map<String, dynamic>> _getVersionManifest() async {
    // First check local cache
    final localVersionFile = File('${_i18nDir.path}/version.json');
    if (await localVersionFile.exists()) {
      try {
        final content = await localVersionFile.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      } catch (e) {
        // Corrupted, try GitHub
      }
    }

    // Try GitHub
    try {
      final url = '$kBaseUrl/i18n/version.json';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        await localVersionFile.writeAsString(response.body);
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      // Network unavailable
    }

    // Return default - use bundled/local files
    return {'version': '1.0.0', 'languages': {}};
  }
        'Failed to download i18n version.json: HTTP ${response.statusCode}',
      );
    }

    // Cache the version file locally
    await localVersionFile.writeAsString(response.body);

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Download a single language file
  Future<void> downloadLanguage(String langCode) async {
    await _ensureI18nDir();

    final url = '$kBaseUrl/i18n/$langCode.json';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download i18n/$langCode.json: HTTP ${response.statusCode}',
      );
    }

    // Parse and validate that version field exists
    final data = json.decode(response.body) as Map<String, dynamic>;

    if (!data.containsKey('version')) {
      throw Exception(
        'Invalid i18n file: missing "version" field in $langCode.json',
      );
    }

    // Save to cache
    final file = File('${_i18nDir.path}/$langCode.json');
    await file.writeAsString(response.body);
  }

  /// Sync i18n files - download only modified ones
  /// Returns list of updated language codes
  Future<List<String>> syncI18n() async {
    final updated = <String>[];

    try {
      // Get version manifest from GitHub
      final remoteManifest = await _getVersionManifest();
      final localVersionFile = File('${_i18nDir.path}/version.json');

      final remoteFiles = remoteManifest['files'] as Map<String, dynamic>;
      final remoteVersion = remoteManifest['version'] as String;

      // Check each language
      for (final langCode in supportedLanguages) {
        if (!remoteFiles.containsKey(langCode)) continue;

        final remoteLangVersion = remoteFiles[langCode] as String;
        bool needsDownload = true;

        // Check if local file exists and compare version
        final localFile = File('${_i18nDir.path}/$langCode.json');
        if (await localFile.exists()) {
          // Parse local file to get version
          final localContent = await localFile.readAsString();
          final localData = json.decode(localContent) as Map<String, dynamic>;
          final localLangVersion = localData['version'] as String?;

          if (localLangVersion == remoteLangVersion) {
            needsDownload = false;
          }
        }

        if (needsDownload) {
          await downloadLanguage(langCode);
          updated.add(langCode);
        }
      }

      // Update local version manifest
      await localVersionFile.writeAsString(
        json.encode({
          'version': remoteVersion,
          'last_updated': DateTime.now().toIso8601String(),
          'files': remoteFiles,
        }),
      );
    } catch (e) {
      // If sync fails, check if we have at least English
      if (!await _hasLanguage(fallbackLanguage)) {
        rethrow;
      }
    }

    return updated;
  }

  /// Check if a language file is available locally
  Future<bool> _hasLanguage(String langCode) async {
    final file = File('${_i18nDir.path}/$langCode.json');
    return file.exists();
  }

  /// Load i18n strings for a language
  /// Falls back to English if requested language is not available
  Future<Map<String, String>> load(String langCode) async {
    // Try requested language first
    if (await _hasLanguage(langCode)) {
      return _loadLanguageFile(langCode);
    }

    // Fallback to English
    if (langCode != fallbackLanguage && await _hasLanguage(fallbackLanguage)) {
      return _loadLanguageFile(fallbackLanguage);
    }

    // Last resort: try to download English
    if (langCode != fallbackLanguage) {
      await downloadLanguage(fallbackLanguage);
      return _loadLanguageFile(fallbackLanguage);
    }

    throw Exception('Unable to load i18n: no language files available');
  }

  /// Load a language file from cache
  Future<Map<String, String>> _loadLanguageFile(String langCode) async {
    final file = File('${_i18nDir.path}/$langCode.json');
    final content = await file.readAsString();
    final data = json.decode(content) as Map<String, dynamic>;

    // Filter out non-string keys and return
    final result = <String, String>{};
    for (final entry in data.entries) {
      if (entry.value is String) {
        result[entry.key] = entry.value as String;
      }
    }

    return result;
  }

  /// Get list of available languages in cache
  Future<List<String>> get availableLanguages async {
    final languages = <String>[];

    for (final langCode in supportedLanguages) {
      if (await _hasLanguage(langCode)) {
        languages.add(langCode);
      }
    }

    return languages;
  }
}
