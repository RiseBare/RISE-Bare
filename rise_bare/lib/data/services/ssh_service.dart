import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

class SSHService {
  SSHClient? _client;
  SSHSession? _session;
  final String host;
  final int port;
  final String username;
  final String password;

  bool get isConnected => _client != null;

  SSHService({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
  });

  Future<bool> connect() async {
    try {
      _client = SSHClient(
        await SSHSocket.connect(host, port),
        username: username,
        onPasswordRequest: () => password,
      );
      return true;
    } catch (e) {
      debugPrint('SSH connection failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _session?.close();
    _client?.close();
    _client = null;
    _session = null;
  }

  Future<SSHResult> execute(String command) async {
    if (_client == null) {
      return SSHResult(
        success: false,
        output: 'Not connected',
        exitCode: -1,
      );
    }

    try {
      _session = await _client!.execute(command);

      final outputBuffer = StringBuffer();
      final errorBuffer = StringBuffer();

      _session!.stdout.listen((data) {
        outputBuffer.write(utf8.decode(data));
      });

      _session!.stderr.listen((data) {
        errorBuffer.write(utf8.decode(data));
      });

      final exitCodeFuture = _session!.exitCode;
      final exitCode = exitCodeFuture != null ? await exitCodeFuture : -1;

      return SSHResult(
        success: exitCode == 0,
        output: outputBuffer.toString(),
        error: errorBuffer.toString(),
        exitCode: exitCode,
      );
    } catch (e) {
      return SSHResult(
        success: false,
        output: '',
        error: e.toString(),
        exitCode: -1,
      );
    }
  }

  /// Check if RISE is installed on the server
  Future<bool> checkRISEInstalled() async {
    final result = await execute('test -f /usr/local/bin/rise-health.sh && echo "installed" || echo "not_installed"');
    return result.output.trim() == 'installed';
  }

  /// Get RISE version
  Future<String?> getRISEVersion() async {
    final result = await execute('/usr/local/bin/rise-health.sh --version 2>/dev/null');
    if (result.success) {
      return result.output.trim();
    }
    return null;
  }

  /// Run rise-health.sh
  Future<Map<String, dynamic>> runHealthCheck() async {
    final result = await execute('/usr/local/bin/rise-health.sh');

    // Parse health check output
    final lines = result.output.split('\n');
    final health = <String, dynamic>{};

    for (final line in lines) {
      if (line.contains(':')) {
        final parts = line.split(':');
        final key = parts[0].trim().toLowerCase().replaceAll(' ', '_');
        final value = parts.sublist(1).join(':').trim();
        health[key] = value;
      }
    }

    return health;
  }

  /// Run rise-firewall.sh with arguments
  Future<SSHResult> runFirewallCommand(String subcommand, [String? args]) {
    final cmd = '/usr/local/bin/rise-firewall.sh $subcommand ${args ?? ''}';
    return execute(cmd);
  }

  /// Run rise-docker.sh with arguments
  Future<SSHResult> runDockerCommand(String subcommand, [String? args]) {
    final cmd = '/usr/local/bin/rise-docker.sh $subcommand ${args ?? ''}';
    return execute(cmd);
  }

  /// Run rise-update.sh with arguments
  Future<SSHResult> runUpdateCommand(String subcommand, [String? args]) {
    final cmd = '/usr/local/bin/rise-update.sh $subcommand ${args ?? ''}';
    return execute(cmd);
  }
}

class SSHResult {
  final bool success;
  final String output;
  final String error;
  final int exitCode;

  SSHResult({
    required this.success,
    required this.output,
    this.error = '',
    required this.exitCode,
  });

  @override
  String toString() {
    return 'SSHResult(success: $success, exitCode: $exitCode, output: $output, error: $error)';
  }
}
