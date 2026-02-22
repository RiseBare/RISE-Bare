import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class StorageService {
  static const String _serversFileName = 'servers.json';
  static const String _settingsFileName = 'settings.json';

  final FlutterSecureStorage _secureStorage;
  String? _appDataPath;

  StorageService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  /// Initialize storage - must be called before using other methods
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _appDataPath = '${appDir.path}/rise_bare';

    // Create directory if it doesn't exist
    final dir = Directory(_appDataPath!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  String get _serversPath => '$_appDataPath/$_serversFileName';
  String get _settingsPath => '$_appDataPath/$_settingsFileName';

  // ==================== Servers ====================

  /// Load all servers from storage
  Future<List<Map<String, dynamic>>> loadServers() async {
    try {
      final file = File(_serversPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> list = json.decode(content);
        return list.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('Error loading servers: $e');
    }
    return [];
  }

  /// Save servers to storage
  Future<void> saveServers(List<Map<String, dynamic>> servers) async {
    try {
      final file = File(_serversPath);
      await file.writeAsString(json.encode(servers));
    } catch (e) {
      debugPrint('Error saving servers: $e');
    }
  }

  /// Add a server
  Future<void> addServer(Map<String, dynamic> server) async {
    final servers = await loadServers();
    servers.add(server);
    await saveServers(servers);
  }

  /// Update a server
  Future<void> updateServer(String id, Map<String, dynamic> server) async {
    final servers = await loadServers();
    final index = servers.indexWhere((s) => s['id'] == id);
    if (index != -1) {
      servers[index] = server;
      await saveServers(servers);
    }
  }

  /// Remove a server
  Future<void> removeServer(String id) async {
    final servers = await loadServers();
    servers.removeWhere((s) => s['id'] == id);
    await saveServers(servers);
  }

  // ==================== SSH Keys ====================

  /// Store SSH private key securely
  Future<void> storeSSHKey(String serverId, String privateKey) async {
    try {
      await _secureStorage.write(
        key: 'ssh_key_$serverId',
        value: privateKey,
      );
    } catch (e) {
      debugPrint('Error storing SSH key: $e');
    }
  }

  /// Retrieve SSH private key
  Future<String?> getSSHKey(String serverId) async {
    try {
      return await _secureStorage.read(key: 'ssh_key_$serverId');
    } catch (e) {
      debugPrint('Error reading SSH key: $e');
      return null;
    }
  }

  /// Delete SSH key
  Future<void> deleteSSHKey(String serverId) async {
    try {
      await _secureStorage.delete(key: 'ssh_key_$serverId');
    } catch (e) {
      debugPrint('Error deleting SSH key: $e');
    }
  }

  /// Store known hosts
  Future<void> storeKnownHosts(Map<String, String> hosts) async {
    try {
      await _secureStorage.write(
        key: 'known_hosts',
        value: json.encode(hosts),
      );
    } catch (e) {
      debugPrint('Error storing known hosts: $e');
    }
  }

  /// Get known hosts
  Future<Map<String, String>> getKnownHosts() async {
    try {
      final data = await _secureStorage.read(key: 'known_hosts');
      if (data != null) {
        final Map<String, dynamic> decoded = json.decode(data);
        return decoded.map((key, value) => MapEntry(key, value.toString()));
      }
    } catch (e) {
      debugPrint('Error reading known hosts: $e');
    }
    return {};
  }

  // ==================== Settings ====================

  /// Load settings
  Future<Map<String, dynamic>> loadSettings() async {
    try {
      final file = File(_settingsPath);
      if (await file.exists()) {
        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
    return _defaultSettings;
  }

  /// Save settings
  Future<void> saveSettings(Map<String, dynamic> settings) async {
    try {
      final file = File(_settingsPath);
      await file.writeAsString(json.encode(settings));
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  /// Default settings
  static Map<String, dynamic> get _defaultSettings => {
    'language': 'en',
    'theme': 'system',
    'autoUpdateScripts': true,
    'checkUpdatesOnStartup': true,
  };

  /// Clear all data
  Future<void> clearAll() async {
    try {
      final dir = Directory(_appDataPath!);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
      await _secureStorage.deleteAll();
    } catch (e) {
      debugPrint('Error clearing data: $e');
    }
  }
}
