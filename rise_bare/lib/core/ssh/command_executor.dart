import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

/// Command timeout types as specified in specs Section 10.3
enum CommandType {
  /// 10s — --scan, --list, --check (health)
  quick,
  
  /// 30s — --start, --stop, --generate-otp, --finalize
  medium,
  
  /// 120s — --compose-scan
  long,
  
  /// 220s — --check (apt)
  updateCheck,
  
  /// 660s — --upgrade (apt)
  upgrade,
}

/// Duration for each command type
extension CommandTypeExtension on CommandType {
  Duration get timeout {
    switch (this) {
      case CommandType.quick:
        return const Duration(seconds: 10);
      case CommandType.medium:
        return const Duration(seconds: 30);
      case CommandType.long:
        return const Duration(seconds: 120);
      case CommandType.updateCheck:
        return const Duration(seconds: 220);
      case CommandType.upgrade:
        return const Duration(seconds: 660);
    }
  }
}

/// Executes commands via SSH with proper timeout handling and JSON parsing.
/// All RISE commands are prefixed with 'sudo'.
class CommandExecutor {
  CommandExecutor();

  /// Execute a RISE command with appropriate timeout.
  /// 
  /// [client] - The SSH client to use
  /// [command] - The command to execute (without 'sudo' prefix - added automatically)
  /// [timeout] - The timeout type determining max execution time
  /// 
  /// Returns a Map<String, dynamic> parsed from JSON response.
  /// Throws RiseCommandException if status == "error" in JSON.
  /// Throws TimeoutException if command exceeds timeout.
  Future<Map<String, dynamic>> run(
    SSHClient client,
    String command, {
    required CommandType timeout,
  }) async {
    // Prefix with sudo as per specs
    final fullCommand = 'sudo $command';

    try {
      final result = await _executeWithTimeout(client, fullCommand, timeout.timeout);
      
      // Parse JSON response
      return _parseResponse(result);
    } on TimeoutException {
      rethrow;
    } catch (e) {
      throw RiseCommandException(
        message: 'Command execution failed: $e',
        command: command,
      );
    }
  }

  /// Execute command and return raw stdout string.
  Future<String> runRaw(
    SSHClient client,
    String command, {
    required CommandType timeout,
  }) async {
    final fullCommand = 'sudo $command';
    return await _executeWithTimeout(client, fullCommand, timeout.timeout);
  }

  /// Internal method to execute with timeout.
  Future<String> _executeWithTimeout(
    SSHClient client,
    String command,
    Duration timeout,
  ) async {
    final completer = Completer<String>();
    final timeoutHandle = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Command timed out after ${timeout.inSeconds} seconds: $command'),
        );
      }
    });

    try {
      final session = await client.execute(command);
      
      final outputBuffer = StringBuffer();
      final errorBuffer = StringBuffer();

      session.stdout.listen(
        (data) => outputBuffer.write(utf8.decode(data)),
        onDone: () {},
      );

      session.stderr.listen(
        (data) => errorBuffer.write(utf8.decode(data)),
        onDone: () {},
      );

      final exitCode = await session.exitCode;
      timeoutHandle.cancel();

      if (exitCode != 0 && errorBuffer.isNotEmpty) {
        completer.completeError(
          RiseCommandException(
            message: 'Command failed with exit code $exitCode: ${errorBuffer.toString()}',
            command: command,
            exitCode: exitCode,
          ),
        );
      } else {
        completer.complete(outputBuffer.toString());
      }
    } catch (e) {
      timeoutHandle.cancel();
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }

    return completer.future;
  }

  /// Parse JSON response and check for errors.
  Map<String, dynamic> _parseResponse(String output) {
    final trimmed = output.trim();
    
    if (trimmed.isEmpty) {
      throw RiseCommandException(
        message: 'Empty response from server',
        rawOutput: output,
      );
    }

    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      
      // Check for error status as per specs
      if (json['status'] == 'error') {
        final errorCode = json['error'] as String? ?? 'UNKNOWN';
        final errorMessage = json['message'] as String? ?? 'Unknown error';
        
        throw RiseCommandException(
          message: errorMessage,
          command: '',
          errorCode: errorCode,
          rawOutput: output,
        );
      }

      return json;
    } catch (e) {
      if (e is RiseCommandException) rethrow;
      
      // If not valid JSON, return as-is with raw output
      throw RiseCommandException(
        message: 'Failed to parse JSON response: $e',
        rawOutput: output,
      );
    }
  }
}

/// Exception thrown when a RISE command fails.
class RiseCommandException implements Exception {
  final String message;
  final String command;
  final String? errorCode;
  final int? exitCode;
  final String? rawOutput;

  RiseCommandException({
    required this.message,
    this.command = '',
    this.errorCode,
    this.exitCode,
    this.rawOutput,
  });

  /// Check if this is a retryable error (ERR_LOCKED)
  bool get isRetryable => errorCode == 'ERR_LOCKED';

  /// Check if this is a dependency error (ERR_DEPENDENCY)
  bool get isDependencyError => errorCode == 'ERR_DEPENDENCY';

  /// Check if pending rules expired (ERR_PENDING_EXPIRED)
  bool get isPendingExpired => errorCode == 'ERR_PENDING_EXPIRED';

  /// Check if already configured (ERR_ALREADY_CONFIGURED)
  bool get isAlreadyConfigured => errorCode == 'ERR_ALREADY_CONFIGURED';

  /// Check if root has no key warning (WARN_ROOT_NO_KEY)
  bool get isRootNoKeyWarning => errorCode == 'WARN_ROOT_NO_KEY';

  @override
  String toString() {
    if (errorCode != null) {
      return 'RiseCommandException($errorCode): $message';
    }
    return 'RiseCommandException: $message';
  }
}

/// API version checking as per specs Section 10.4
class ApiVersionChecker {
  /// Check if server API version is compatible.
  /// 
  /// [serverVersion] - Version string from server (e.g., "1.2.3")
  /// 
  /// Returns ApiVersionResult indicating compatibility.
  ApiVersionResult check(String serverVersion) {
    final clientVersion = '1.0.0'; // Should match app version
    
    final clientParts = clientVersion.split('.').map(int.parse).toList();
    final serverParts = serverVersion.split('.').map(int.parse).toList();

    final clientMajor = clientParts[0];
    final clientMinor = clientParts[1];
    final serverMajor = serverParts[0];
    final serverMinor = serverParts[1];

    // Major version different - incompatible
    if (clientMajor != serverMajor) {
      return ApiVersionResult(
        isCompatible: false,
        isBlocking: true,
        serverVersion: serverVersion,
        clientVersion: clientVersion,
        message: 'Incompatible API version: server $serverVersion, client $clientVersion',
      );
    }

    // Minor drift > 2 - warning but allow operation
    final minorDrift = (serverMinor - clientMinor).abs();
    if (minorDrift > 2) {
      return ApiVersionResult(
        isCompatible: true,
        isBlocking: false,
        serverVersion: serverVersion,
        clientVersion: clientVersion,
        message: 'API version mismatch (drift: $minorDrift minor versions)',
      );
    }

    return ApiVersionResult(
      isCompatible: true,
      isBlocking: false,
      serverVersion: serverVersion,
      clientVersion: clientVersion,
    );
  }
}

/// Result of API version check
class ApiVersionResult {
  final bool isCompatible;
  final bool isBlocking;
  final String serverVersion;
  final String clientVersion;
  final String message;

  ApiVersionResult({
    required this.isCompatible,
    required this.isBlocking,
    required this.serverVersion,
    required this.clientVersion,
    this.message = '',
  });
}
