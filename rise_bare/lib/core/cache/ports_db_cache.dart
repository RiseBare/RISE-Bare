import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'cache_manager.dart';

/// Cache for ports_db.json
class PortsDbCache {
  late final File _portsDbFile;

  PortsDbCache(Directory baseDir) {
    _portsDbFile = File('${baseDir.path}/ports_db.json');
  }

  /// Ensure ports_db.json exists in cache
  Future<void> _ensurePortsDbFile() async {
    if (!await _portsDbFile.exists()) {
      // Download initial file
      await downloadPortsDb();
    }
  }

  /// Download ports_db.json from GitHub
  Future<void> downloadPortsDb() async {
    final url = '$kBaseUrl/ports_db.json';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception(
        'Failed to download ports_db.json: HTTP ${response.statusCode}',
      );
    }

    // Validate JSON structure
    final data = json.decode(response.body) as Map<String, dynamic>;

    if (!data.containsKey('version')) {
      throw Exception('Invalid ports_db.json: missing "version" field');
    }

    if (!data.containsKey('last_updated')) {
      throw Exception('Invalid ports_db.json: missing "last_updated" field');
    }

    if (!data.containsKey('ports')) {
      throw Exception('Invalid ports_db.json: missing "ports" field');
    }

    // Save to cache
    await _portsDbFile.writeAsString(response.body);
  }

  /// Sync ports_db.json - download if version changed
  /// Returns true if updated
  Future<bool> sync() async {
    try {
      // Get remote version
      final url = '$kBaseUrl/ports_db.json';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to download ports_db.json: HTTP ${response.statusCode}',
        );
      }

      final remoteData = json.decode(response.body) as Map<String, dynamic>;
      final remoteVersion = remoteData['version'] as String;

      // Check local version
      if (await _portsDbFile.exists()) {
        final localContent = await _portsDbFile.readAsString();
        final localData = json.decode(localContent) as Map<String, dynamic>;
        final localVersion = localData['version'] as String?;

        // Same version - no need to update
        if (localVersion == remoteVersion) {
          return false;
        }
      }

      // Download new version
      await downloadPortsDb();
      return true;
    } catch (e) {
      // If sync fails but we have a local file, use it
      if (await _portsDbFile.exists()) {
        return false;
      }
      rethrow;
    }
  }

  /// Get list of ports from cached ports_db.json
  Future<List<Map<String, dynamic>>> getPorts() async {
    await _ensurePortsDbFile();

    final content = await _portsDbFile.readAsString();
    final data = json.decode(content) as Map<String, dynamic>;

    final ports = data['ports'];
    if (ports is! List) {
      return [];
    }

    return ports.cast<Map<String, dynamic>>();
  }

  /// Get port by number
  Future<Map<String, dynamic>?> getPortByNumber(int portNumber) async {
    final ports = await getPorts();

    for (final port in ports) {
      if (port['port'] == portNumber) {
        return port;
      }
    }

    return null;
  }

  /// Get port by name/service
  Future<List<Map<String, dynamic>>> getPortsByName(String name) async {
    final ports = await getPorts();
    final nameLower = name.toLowerCase();

    return ports.where((port) {
      final service = port['service'] as String?;
      return service?.toLowerCase().contains(nameLower) ?? false;
    }).toList();
  }

  /// Get the cached version
  Future<String?> getVersion() async {
    if (!await _portsDbFile.exists()) {
      return null;
    }

    final content = await _portsDbFile.readAsString();
    final data = json.decode(content) as Map<String, dynamic>;

    return data['version'] as String?;
  }

  /// Get the last_updated timestamp
  Future<DateTime?> getLastUpdated() async {
    if (!await _portsDbFile.exists()) {
      return null;
    }

    final content = await _portsDbFile.readAsString();
    final data = json.decode(content) as Map<String, dynamic>;

    final lastUpdated = data['last_updated'] as String?;
    if (lastUpdated == null) {
      return null;
    }

    return DateTime.tryParse(lastUpdated);
  }
}
