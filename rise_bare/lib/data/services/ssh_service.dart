import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/ssh/key_manager.dart';
import '../../core/ssh/tofu_verifier.dart';
import '../../core/ssh/command_executor.dart';

/// SSH Service for RISE operations.
/// Supports both password and Ed25519 key authentication.
class SSHService {
  SSHClient? _client;
  SSHSession? _session;
  
  final String host;
  final int port;
  final String username;
  final String? password;

  final KeyManager keyManager;
  final TofuVerifier tofuVerifier;
  final CommandExecutor commandExecutor;

  bool get isConnected => _client != null;

  SSHService({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    KeyManager? keyManager,
    TofuVerifier? tofuVerifier,
    CommandExecutor? commandExecutor,
  })  : keyManager = keyManager ?? KeyManager(),
        tofuVerifier = tofuVerifier ?? TofuVerifier(),
        commandExecutor = commandExecutor ?? CommandExecutor();

  /// Initialize the service (load TOFU hosts, ensure key pair).
  Future<void> initialize() async {
    await tofuVerifier.initialize();
    await keyManager.ensureKeyPair();
  }

  /// Connect using password authentication.
  Future<bool> connectWithPassword() async {
    try {
      final socket = await SSHSocket.connect(host, port);
      
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password ?? '',
      );
      
      // Test connection
      await _client!.execute('echo test');
      return true;
    } catch (e) {
      debugPrint('SSH connection failed: $e');
      return false;
    }
  }

  /// Connect using Ed25519 key authentication.
  Future<bool> connectWithKey() async {
    try {
      final socket = await SSHSocket.connect(host, port);
      
      // Load private key
      final keyPair = await keyManager.loadPrivateKey();

      _client = SSHClient(
        socket,
        username: username,
        identities: [keyPair],
      );
      
      // Test connection
      await _client!.execute('echo test');
      return true;
    } catch (e) {
      debugPrint('SSH key connection failed: $e');
      return false;
    }
  }

  /// Connect using best available method.
  Future<bool> connect() async {
    final hasKey = await keyManager.hasKeyPair();
    if (hasKey) {
      return await connectWithKey();
    } else if (password != null) {
      return await connectWithPassword();
    }
    return false;
  }

  Future<void> disconnect() async {
    _session?.close();
    _client?.close();
    _client = null;
    _session = null;
  }

  /// Execute a command and parse JSON response.
  /// Handles ERR_LOCKED with automatic retry.
  Future<SSHResult> executeWithRetry(
    String command, {
    CommandType timeout = CommandType.quick,
    int maxRetries = 3,
  }) async {
    int attempt = 0;
    Duration retryDelay = const Duration(seconds: 2);

    while (attempt < maxRetries) {
      try {
        final result = await execute(command, timeout: timeout);
        
        // Check for retryable error
        if (result.errorCode != null) {
          final errorCode = result.errorCode;
          if (errorCode == 'ERR_LOCKED') {
            attempt++;
            if (attempt < maxRetries) {
              debugPrint('ERR_LOCKED - retrying in ${retryDelay.inSeconds}s (attempt $attempt/$maxRetries)');
              await Future.delayed(retryDelay);
              retryDelay *= 1.5; // Exponential backoff
              continue;
            }
          }
        }
        
        return result;
      } catch (e) {
        if (e is RiseCommandException && e.isRetryable && attempt < maxRetries - 1) {
          attempt++;
          debugPrint('Retryable error - retrying (attempt $attempt/$maxRetries)');
          await Future.delayed(retryDelay);
          retryDelay *= 1.5;
          continue;
        }
        rethrow;
      }
    }
    
    return SSHResult(
      success: false,
      output: '',
      error: 'Max retries exceeded',
      exitCode: -1,
    );
  }

  /// Execute a command and parse JSON response.
  Future<SSHResult> execute(String command, {CommandType timeout = CommandType.quick}) async {
    if (_client == null) {
      return SSHResult(
        success: false,
        output: 'Not connected',
        exitCode: -1,
      );
    }

    try {
      // Prefix with sudo as per specs
      final fullCommand = 'sudo $command';
      
      // Execute with timeout
      final result = await _executeWithTimeout(fullCommand, timeout.timeout);
      
      // Parse JSON response
      return _parseJsonResult(result);
    } on TimeoutException catch (e) {
      return SSHResult(
        success: false,
        output: '',
        error: 'Command timed out: ${e.message}',
        exitCode: -1,
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

  /// Execute command with timeout.
  Future<String> _executeWithTimeout(String command, Duration timeout) async {
    final completer = Completer<String>();
    final timeoutHandle = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Command timed out after ${timeout.inSeconds}s'),
        );
      }
    });

    try {
      final session = await _client!.execute(command);
      
      final outputBuffer = StringBuffer();
      final errorBuffer = StringBuffer();

      session.stdout.listen((data) {
        outputBuffer.write(utf8.decode(data));
      });

      session.stderr.listen((data) {
        errorBuffer.write(utf8.decode(data));
      });

      final exitCode = await session.exitCode;
      timeoutHandle.cancel();

      if (exitCode != 0 && errorBuffer.isNotEmpty) {
        return errorBuffer.toString();
      }
      return outputBuffer.toString();
    } catch (e) {
      timeoutHandle.cancel();
      rethrow;
    }
  }

  /// Parse JSON result and handle error status.
  SSHResult _parseJsonResult(String output) {
    final trimmed = output.trim();
    
    if (trimmed.isEmpty) {
      return SSHResult(
        success: false,
        output: '',
        error: 'Empty response from server',
        exitCode: -1,
      );
    }

    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      
      // Check for error status as per specs
      if (json['status'] == 'error') {
        final errorCode = json['error'] as String? ?? 'UNKNOWN';
        final errorMessage = json['message'] as String? ?? 'Unknown error';
        
        return SSHResult(
          success: false,
          output: trimmed,
          error: errorMessage,
          exitCode: -1,
          errorCode: errorCode,
        );
      }

      return SSHResult(
        success: true,
        output: trimmed,
        exitCode: 0,
      );
    } catch (e) {
      // Not JSON - treat as raw output
      return SSHResult(
        success: true,
        output: trimmed,
        exitCode: 0,
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

  /// Verify API version compatibility.
  Future<ApiVersionResult> checkApiVersion() async {
    final checker = ApiVersionChecker();
    final version = await getRISEVersion();
    
    if (version == null) {
      return ApiVersionResult(
        isCompatible: false,
        isBlocking: true,
        serverVersion: 'unknown',
        clientVersion: '1.0.0',
        message: 'Could not determine server version',
      );
    }
    
    return checker.check(version);
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

  /// Run rise-onboard.sh with arguments
  Future<SSHResult> runOnboardCommand(String subcommand, [String? args]) {
    final cmd = '/usr/local/bin/rise-onboard.sh $subcommand ${args ?? ''}';
    return execute(cmd);
  }

  /// Upload a file via SFTP.
  Future<void> uploadFile(String localPath, String remotePath) async {
    if (_client == null) {
      throw SSHException('Not connected');
    }

    final sftp = await _client!.sftp();
    final localFile = File(localPath);
    final bytes = await localFile.readAsBytes();
    
    final remoteFile = await sftp.open(remotePath, mode: SftpFileOpenMode.create | SftpFileOpenMode.write);
    await remoteFile.write(Stream.value(bytes));
    await remoteFile.close();
  }

  /// Get public key string for authorized_keys.
  Future<String> getPublicKeyString() async {
    return await keyManager.getPublicKeyString();
  }
}

class SSHResult {
  final bool success;
  final String output;
  final String error;
  final int exitCode;
  final String? errorCode;

  SSHResult({
    required this.success,
    required this.output,
    this.error = '',
    required this.exitCode,
    this.errorCode,
  });

  /// Parse output as JSON map
  Map<String, dynamic>? get json {
    try {
      return jsonDecode(output) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Check if this is ERR_LOCKED
  bool get isLocked => errorCode == 'ERR_LOCKED';

  /// Check if this is ERR_DEPENDENCY
  bool get isDependencyError => errorCode == 'ERR_DEPENDENCY';

  /// Check if this is ERR_PENDING_EXPIRED
  bool get isPendingExpired => errorCode == 'ERR_PENDING_EXPIRED';

  /// Check if this is ERR_ALREADY_CONFIGURED
  bool get isAlreadyConfigured => errorCode == 'ERR_ALREADY_CONFIGURED';

  /// Check if this is WARN_ROOT_NO_KEY
  bool get isRootNoKeyWarning => errorCode == 'WARN_ROOT_NO_KEY';

  @override
  String toString() {
    return 'SSHResult(success: $success, exitCode: $exitCode, errorCode: $errorCode, output: $output, error: $error)';
  }
}

class SSHException implements Exception {
  final String message;
  SSHException(this.message);
  
  @override
  String toString() => 'SSHException: $message';
}
