import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Trust On First Use (TOFU) verifier for SSH host keys.
/// Handles known_hosts.json to track trusted server fingerprints.
class TofuVerifier {
  static const String _knownHostsFile = 'known_hosts.json';
  
  Map<String, KnownHostEntry> _knownHosts = {};

  TofuVerifier();

  /// Initialize by loading known hosts from disk.
  Future<void> initialize() async {
    await _loadKnownHosts();
  }

  /// Verify a server's fingerprint against known hosts.
  /// Returns TofuResult indicating whether to proceed, reject, or prompt user.
  Future<TofuResult> verify({
    required String host,
    required int port,
    required String fingerprint,
    required String algorithm,
  }) async {
    final key = '${host}:$port';
    final existing = _knownHosts[key];

    if (existing == null) {
      // New host - need user confirmation
      return TofuResult(
        status: TofuStatus.newHost,
        needsUserConfirmation: true,
        message: 'New server detected. Add to trusted hosts?',
      );
    }

    // Check if fingerprint changed (potential MITM)
    if (existing.fingerprint != fingerprint) {
      return TofuResult(
        status: TofuStatus.fingerprintChanged,
        needsUserConfirmation: false,
        message: 'WARNING: Server fingerprint has changed! Possible MITM attack.',
        existingHost: existing,
      );
    }

    // Check if algorithm changed (potential downgrade attack)
    if (existing.algorithm != algorithm) {
      return TofuResult(
        status: TofuStatus.algorithmChanged,
        needsUserConfirmation: false,
        message: 'WARNING: Server key algorithm changed! Possible downgrade attack.',
        existingHost: existing,
      );
    }

    // Fingerprint and algorithm match - proceed
    return TofuResult(
      status: TofuStatus.trusted,
      needsUserConfirmation: false,
    );
  }

  /// Add a new host to known hosts after user confirmation.
  Future<void> addHost({
    required String host,
    required int port,
    required String fingerprint,
    required String algorithm,
  }) async {
    final key = '${host}:$port';
    _knownHosts[key] = KnownHostEntry(
      host: host,
      port: port,
      fingerprint: fingerprint,
      algorithm: algorithm,
      firstSeen: DateTime.now(),
    );
    await _saveKnownHosts();
  }

  /// Remove a host from known hosts (e.g., when server is reconfigured).
  Future<void> removeHost(String host, int port) async {
    final key = '${host}:$port';
    _knownHosts.remove(key);
    await _saveKnownHosts();
  }

  /// Get all known hosts.
  List<KnownHostEntry> getKnownHosts() {
    return _knownHosts.values.toList();
  }

  /// Check if a host is known.
  bool isHostKnown(String host, int port) {
    final key = '${host}:$port';
    return _knownHosts.containsKey(key);
  }

  /// Load known hosts from disk.
  Future<void> _loadKnownHosts() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_knownHostsFile');
      
      if (!await file.exists()) {
        _knownHosts = {};
      return;
    }

    final content = await file.readAsString();
      final List<dynamic> json = jsonDecode(content);
      
      _knownHosts = {};
      for (final entry in json) {
        final hostEntry = KnownHostEntry.fromJson(entry);
        final key = '${hostEntry.host}:${hostEntry.port}';
        _knownHosts[key] = hostEntry;
      }
    } catch (e) {
      _knownHosts = {};
    }
  }

  /// Save known hosts to disk.
  Future<void> _saveKnownHosts() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_knownHostsFile');
      
      final json = _knownHosts.values.map((h) => h.toJson()).toList();
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      // Log error but don't crash
      print('Failed to save known hosts: $e');
    }
  }
}

/// Represents a known host entry.
class KnownHostEntry {
  final String host;
  final int port;
  final String fingerprint;
  final String algorithm;
  final DateTime firstSeen;

  KnownHostEntry({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.algorithm,
    required this.firstSeen,
  });

  factory KnownHostEntry.fromJson(Map<String, dynamic> json) {
    return KnownHostEntry(
      host: json['host'] as String,
      port: json['port'] as int,
      fingerprint: json['fingerprint'] as String,
      algorithm: json['algorithm'] as String,
      firstSeen: DateTime.parse(json['firstSeen'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'fingerprint': fingerprint,
      'algorithm': algorithm,
      'firstSeen': firstSeen.toIso8601String(),
    };
  }
}

/// Result of TOFU verification.
class TofuResult {
  final TofuStatus status;
  final bool needsUserConfirmation;
  final String message;
  final KnownHostEntry? existingHost;

  TofuResult({
    required this.status,
    required this.needsUserConfirmation,
    this.message = '',
    this.existingHost,
  });
}

/// Status of TOFU verification.
enum TofuStatus {
  trusted,           // Host is known and fingerprint matches
  newHost,           // New host - needs user confirmation
  fingerprintChanged, // MITM attack possible
  algorithmChanged,   // Downgrade attack possible
}
