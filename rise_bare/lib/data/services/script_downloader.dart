import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ScriptDownloader {
  static const String _baseUrl = 'https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/scripts';
  static const String _manifestUrl = 'https://raw.githubusercontent.com/RiseBare/RISE-Bare/main/manifest.json';

  final http.Client _client;

  ScriptDownloader({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch the manifest to get script versions and URLs
  Future<Map<String, dynamic>?> fetchManifest() async {
    try {
      final response = await _client.get(Uri.parse(_manifestUrl));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Failed to fetch manifest: $e');
    }
    return null;
  }

  /// Download a script and verify its SHA256
  Future<String?> downloadScript(String scriptName, String expectedSha256) async {
    final url = '$_baseUrl/$scriptName';

    try {
      final response = await _client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('Failed to download $scriptName: ${response.statusCode}');
        return null;
      }

      final content = response.bodyBytes;

      // Verify SHA256
      final hash = sha256.convert(content).toString();
      if (hash != expectedSha256) {
        debugPrint('SHA256 mismatch for $scriptName: expected $expectedSha256, got $hash');
        return null;
      }

      return utf8.decode(content);
    } catch (e) {
      debugPrint('Error downloading $scriptName: $e');
      return null;
    }
  }

  /// Download all scripts to a directory
  Future<Map<String, String>> downloadAllScripts(Map<String, String> scriptsSha256, String outputDir) async {
    final downloaded = <String, String>{};

    for (final entry in scriptsSha256.entries) {
      final scriptName = entry.key;
      final expectedSha256 = entry.value;

      final content = await downloadScript(scriptName, expectedSha256);
      if (content != null) {
        final file = File('$outputDir/$scriptName');
        await file.writeAsString(content);
        await Process.run('chmod', ['+x', file.path]);
        downloaded[scriptName] = file.path;
        debugPrint('Downloaded and verified: $scriptName');
      }
    }

    return downloaded;
  }

  /// Check if a newer version is available
  Future<ScriptUpdateInfo?> checkForUpdates(String currentVersion) async {
    final manifest = await fetchManifest();
    if (manifest == null) return null;

    // Compare versions - for now just return info that update is available
    // Version comparison logic can be added later
    return ScriptUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: manifest['version'] as String? ?? currentVersion,
      hasUpdate: false,
    );
  }

  void dispose() {
    _client.close();
  }
}

class ScriptUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;

  ScriptUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
  });
}
