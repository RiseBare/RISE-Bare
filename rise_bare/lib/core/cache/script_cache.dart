import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'cache_manager.dart';

/// Exception thrown when cache integrity check fails
class CacheIntegrityException implements Exception {
  final String message;
  CacheIntegrityException(this.message);

  @override
  String toString() => 'CacheIntegrityException: $message';
}

/// Cache for shell scripts with SHA256 verification
class ScriptCache {
  final Directory _baseDir;
  late final Directory _scriptsDir;

  /// Required scripts
  static const List<String> requiredScripts = [
    'rise-firewall.sh',
    'rise-docker.sh',
    'rise-update.sh',
    'rise-onboard.sh',
    'rise-health.sh',
    'setup-env.sh',
  ];

  ScriptCache(Directory baseDir) : _baseDir = baseDir {
    _scriptsDir = Directory('${baseDir.path}/scripts');
  }

  /// Get the scripts directory
  Directory get scriptsDir => _scriptsDir;

  /// Ensure scripts directory exists
  Future<void> _ensureScriptsDir() async {
    if (!await _scriptsDir.exists()) {
      await _scriptsDir.create(recursive: true);
    }
  }

  /// Download a single script and verify SHA256
  Future<void> downloadScript(String scriptName) async {
    await _ensureScriptsDir();

    // Get expected SHA256 from manifest
    final manifest = await _getManifest();
    final scriptInfo = manifest['scripts'].firstWhere(
      (s) => s['name'] == scriptName,
      orElse: () => throw CacheIntegrityException(
        'Script $scriptName not found in manifest',
      ),
    );

    final expectedSha256 = scriptInfo['sha256'] as String;
    final url = scriptInfo['url'] as String;

    // Download the script
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw CacheIntegrityException(
        'Failed to download $scriptName: HTTP ${response.statusCode}',
      );
    }

    final bytes = response.bodyBytes;

    // Verify SHA256
    final digest = sha256.convert(bytes);
    if (digest.toString() != expectedSha256) {
      throw CacheIntegrityException(
        'SHA256 mismatch for $scriptName — tampering detected',
      );
    }

    // Save to cache
    final file = File('${_scriptsDir.path}/$scriptName');
    await file.writeAsBytes(bytes);
  }

  /// Get the manifest from GitHub
  Future<Map<String, dynamic>> _getManifest() async {
    // First check local cache
    final localManifestFile = File('${_baseDir.path}/manifest.json');
    if (await localManifestFile.exists()) {
      final content = await localManifestFile.readAsString();
      return json.decode(content) as Map<String, dynamic>;
    }

    // Download from GitHub
    final url = '$kBaseUrl/manifest.json';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw CacheIntegrityException(
        'Failed to download manifest: HTTP ${response.statusCode}',
      );
    }

    // Cache the manifest locally
    await localManifestFile.writeAsString(response.body);

    return json.decode(response.body) as Map<String, dynamic>;
  }

  /// Sync scripts - download only modified ones
  /// Returns list of updated script names
  Future<List<String>> syncScripts() async {
    final updated = <String>[];

    try {
      // Get manifest from GitHub
      final manifest = await _getManifest();
      final localManifestFile = File('${_baseDir.path}/manifest.json');

      final remoteVersion = manifest['version'] as String;

      // Check each script
      for (final scriptInfo in manifest['scripts']) {
        final scriptName = scriptInfo['name'] as String;
        final remoteSha256 = scriptInfo['sha256'] as String;

        final localFile = File('${_scriptsDir.path}/$scriptName');
        bool needsDownload = true;

        if (await localFile.exists()) {
          // Compare SHA256
          final localBytes = await localFile.readAsBytes();
          final localSha256 = sha256.convert(localBytes).toString();

          if (localSha256 == remoteSha256) {
            needsDownload = false;
          }
        }

        if (needsDownload) {
          await downloadScript(scriptName);
          updated.add(scriptName);
        }
      }

      // Update local manifest
      await localManifestFile.writeAsString(
        json.encode({
          'version': remoteVersion,
          'last_updated': DateTime.now().toIso8601String(),
          'scripts': manifest['scripts'],
        }),
      );
    } catch (e) {
      // If sync fails, check if we have all required scripts locally
      if (!await isComplete) {
        rethrow;
      }
    }

    return updated;
  }

  /// Get local path to a script
  Future<String> getLocalPath(String scriptName) async {
    final path = '${_scriptsDir.path}/$scriptName';
    final file = File(path);

    if (!await file.exists()) {
      // Try to download if missing
      await downloadScript(scriptName);
    }

    return path;
  }

  /// Check if all required scripts are cached
  Future<bool> get isComplete async {
    await _ensureScriptsDir();

    for (final script in requiredScripts) {
      final file = File('${_scriptsDir.path}/$script');
      if (!await file.exists()) {
        return false;
      }
    }

    return true;
  }
}
