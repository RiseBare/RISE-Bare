import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'script_cache.dart';
import 'i18n_cache.dart';
import 'ports_db_cache.dart';

/// Base URL for GitHub raw content
const String kBaseUrl = 'https://raw.githubusercontent.com/RiseBare/RISE-Bare/main';

/// Auto-update interval: 6 hours
const Duration kAutoUpdateInterval = Duration(hours: 6);

/// Progress information during cache initialization
class CacheInitProgress {
  final String currentFile;
  final int downloaded;
  final int total;
  final bool isComplete;
  final String? error;

  CacheInitProgress({
    required this.currentFile,
    required this.downloaded,
    required this.total,
    this.isComplete = false,
    this.error,
  });

  CacheInitProgress copyWith({
    String? currentFile,
    int? downloaded,
    int? total,
    bool? isComplete,
    String? error,
  }) {
    return CacheInitProgress(
      currentFile: currentFile ?? this.currentFile,
      downloaded: downloaded ?? this.downloaded,
      total: total ?? this.total,
      isComplete: isComplete ?? this.isComplete,
      error: error ?? this.error,
    );
  }
}

/// Result of update check
class UpdateResult {
  final int scriptsUpdated;
  final List<String> i18nUpdated;
  final bool portsDbUpdated;
  final List<String> notifications;

  UpdateResult({
    required this.scriptsUpdated,
    required this.i18nUpdated,
    required this.portsDbUpdated,
    required this.notifications,
  });
}

/// Main cache orchestrator
class CacheManager {
  late final ScriptCache _scriptCache;
  late final I18nCache _i18nCache;
  late final PortsDbCache _portsDbCache;

  bool _isReady = false;
  bool _isFirstLaunch = false;
  Timer? _autoUpdateTimer;

  bool get isReady => _isReady;
  bool get isFirstLaunch => _isFirstLaunch;

  /// Initialize the cache manager
  Future<void> init() async {
    final baseDir = await _getCacheBaseDir();
    _scriptCache = ScriptCache(baseDir);
    _i18nCache = I18nCache(baseDir);
    _portsDbCache = PortsDbCache(baseDir);
  }

  /// Get the cache base directory
  Future<Directory> _getCacheBaseDir() async {
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${appDir.path}/.rise/cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Initialize cache - downloads all files if first launch
  /// Returns a stream of progress updates
  Stream<CacheInitProgress> initialize() async* {
    // Check if this is first launch (cache is empty)
    _isFirstLaunch = await _isCacheEmpty();

    // Calculate total files to download
    const totalScripts = 6;
    const totalI18n = 10; // 10 languages
    const totalPortsDb = 1;
    final total = totalScripts + totalI18n + totalPortsDb;

    int downloaded = 0;

    // Download scripts
    for (final script in [
      'rise-firewall.sh',
      'rise-docker.sh',
      'rise-update.sh',
      'rise-onboard.sh',
      'rise-health.sh',
      'setup-env.sh',
    ]) {
      yield CacheInitProgress(
        currentFile: script,
        downloaded: downloaded,
        total: total,
      );

      try {
        await _scriptCache.downloadScript(script);
        downloaded++;
      } catch (e) {
        yield CacheInitProgress(
          currentFile: script,
          downloaded: downloaded,
          total: total,
          error: e.toString(),
        );
        rethrow;
      }
    }

    // Download i18n files
    final languages = [
      'en', 'fr', 'de', 'es', 'zh', 'ja', 'ko', 'th', 'pt', 'ru'
    ];
    for (final lang in languages) {
      yield CacheInitProgress(
        currentFile: 'i18n/$lang.json',
        downloaded: downloaded,
        total: total,
      );

      try {
        await _i18nCache.downloadLanguage(lang);
        downloaded++;
      } catch (e) {
        yield CacheInitProgress(
          currentFile: 'i18n/$lang.json',
          downloaded: downloaded,
          total: total,
          error: e.toString(),
        );
        rethrow;
      }
    }

    // Download ports_db.json
    yield CacheInitProgress(
      currentFile: 'ports_db.json',
      downloaded: downloaded,
      total: total,
    );

    try {
      await _portsDbCache.sync();
      downloaded++;
    } catch (e) {
      yield CacheInitProgress(
        currentFile: 'ports_db.json',
        downloaded: downloaded,
        total: total,
        error: e.toString(),
      );
      rethrow;
    }

    // Complete
    _isReady = true;
    yield CacheInitProgress(
      currentFile: '',
      downloaded: total,
      total: total,
      isComplete: true,
    );
  }

  /// Check if cache is empty (first launch)
  Future<bool> _isCacheEmpty() async {
    final baseDir = await _getCacheBaseDir();
    final scriptsDir = Directory('${baseDir.path}/scripts');
    final i18nDir = Directory('${baseDir.path}/i18n');
    final portsDbFile = File('${baseDir.path}/ports_db.json');

    final scriptsEmpty = !await scriptsDir.exists() ||
        (await scriptsDir.list().toList()).isEmpty;
    final i18nEmpty = !await i18nDir.exists() ||
        (await i18nDir.list().toList()).isEmpty;
    final portsDbEmpty = !await portsDbFile.exists();

    return scriptsEmpty && i18nEmpty && portsDbEmpty;
  }

  /// Check for updates and download modified files
  /// Called at startup and every 6 hours
  Future<UpdateResult> checkAndUpdate() async {
    final notifications = <String>[];
    int scriptsUpdated = 0;
    List<String> i18nUpdated = [];
    bool portsDbUpdated = false;

    // Check script updates
    final updatedScripts = await _scriptCache.syncScripts();
    scriptsUpdated = updatedScripts.length;
    for (final script in updatedScripts) {
      notifications.add('Script $script updated');
    }

    // Check i18n updates
    i18nUpdated = await _i18nCache.syncI18n();
    for (final lang in i18nUpdated) {
      notifications.add('Language $lang updated');
    }

    // Check ports_db updates
    final portsUpdated = await _portsDbCache.sync();
    if (portsUpdated) {
      notifications.add('Ports database updated');
      portsDbUpdated = true;
    }

    return UpdateResult(
      scriptsUpdated: scriptsUpdated,
      i18nUpdated: i18nUpdated,
      portsDbUpdated: portsDbUpdated,
      notifications: notifications,
    );
  }

  /// Get list of ports from ports_db.json
  Future<List<Map<String, dynamic>>> getPorts() async {
    return _portsDbCache.getPorts();
  }

  /// Get i18n strings for a language (with fallback to English)
  Future<Map<String, String>> getI18n(String langCode) async {
    return _i18nCache.load(langCode);
  }

  /// Get local path to a script
  Future<String> getScriptPath(String scriptName) async {
    return _scriptCache.getLocalPath(scriptName);
  }

  /// Start auto-update timer (every 6 hours)
  void startAutoUpdate({void Function()? onUpdate}) {
    // Cancel existing timer if any
    _autoUpdateTimer?.cancel();

    // Immediate check
    checkAndUpdate().then((result) {
      if (result.notifications.isNotEmpty) {
        onUpdate?.call();
      }
    });

    // Schedule periodic checks
    _autoUpdateTimer = Timer.periodic(kAutoUpdateInterval, (_) {
      checkAndUpdate().then((result) {
        if (result.notifications.isNotEmpty) {
          onUpdate?.call();
        }
      });
    });
  }

  /// Stop auto-update timer
  void stopAutoUpdate() {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = null;
  }

  /// Dispose resources
  void dispose() {
    stopAutoUpdate();
  }
}
