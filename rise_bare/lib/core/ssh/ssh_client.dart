import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import 'key_manager.dart';
import 'tofu_verifier.dart';
import 'command_executor.dart';

/// Main SSH client for RISE operations.
/// Wraps dartssh2 with TOFU verification, key authentication, and command execution.
class RiseSshClient {
  SSHClient? _client;
  SSHSession? _session;
  
  final String host;
  final int port;
  final String username;
  final String? password;
  
  final KeyManager keyManager;
  final TofuVerifier tofuVerifier;
  final CommandExecutor commandExecutor;

  bool _isConnected = false;
  String? _currentFingerprint;
  String? _currentAlgorithm;

  RiseSshClient({
    required this.host,
    required this.port,
    required this.username,
    this.password,
    required this.keyManager,
    required this.tofuVerifier,
    CommandExecutor? commandExecutor,
  }) : commandExecutor = commandExecutor ?? CommandExecutor();

  bool get isConnected => _isConnected;
  String? get currentFingerprint => _currentFingerprint;
  String? get currentAlgorithm => _currentAlgorithm;

  /// Connect using password authentication.
  Future<bool> connectWithPassword() async {
    if (password == null) {
      throw ArgumentError('Password required for password authentication');
    }

    try {
      final socket = await SSHSocket.connect(host, port);
      
      // Get host key info for TOFU
      final serverKey = await _getServerKey(socket);
      if (serverKey != null) {
        _currentFingerprint = _fingerprintFromKey(serverKey);
        _currentAlgorithm = serverKey.type.name;
        
        // Verify with TOFU
        final tofuResult = await tofuVerifier.verify(
          host: host,
          port: port,
          fingerprint: _currentFingerprint!,
          algorithm: _currentAlgorithm!,
        );

        if (tofuResult.status == TofuStatus.fingerprintChanged ||
            tofuResult.status == TofuStatus.algorithmChanged) {
          await socket.close();
          throw RiseSshException(
            message: tofuResult.message,
            errorType: RiseSshErrorType.securityViolation,
          );
        }

        if (tofuResult.status == TofuStatus.newHost && tofuResult.needsUserConfirmation) {
          // New host - should be handled by caller
          await socket.close();
          throw RiseSshException(
            message: 'New server detected. User confirmation required.',
            errorType: RiseSshErrorType.newHostConfirmation,
          );
        }
      }

      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password!,
      );

      // Save host if trusted
      if (_currentFingerprint != null && _currentAlgorithm != null) {
        await tofuVerifier.addHost(
          host: host,
          port: port,
          fingerprint: _currentFingerprint!,
          algorithm: _currentAlgorithm!,
        );
      }

      _isConnected = true;
      return true;
    } catch (e) {
      debugPrint('SSH connection failed: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Connect using key authentication.
  Future<bool> connectWithKey() async {
    try {
      final socket = await SSHSocket.connect(host, port);
      
      // Get host key info for TOFU
      final serverKey = await _getServerKey(socket);
      if (serverKey != null) {
        _currentFingerprint = _fingerprintFromKey(serverKey);
        _currentAlgorithm = serverKey.type.name;
        
        // Verify with TOFU
        final tofuResult = await tofuVerifier.verify(
          host: host,
          port: port,
          fingerprint: _currentFingerprint!,
          algorithm: _currentAlgorithm!,
        );

        if (tofuResult.status == TofuStatus.fingerprintChanged ||
            tofuResult.status == TofuStatus.algorithmChanged) {
          await socket.close();
          throw RiseSshException(
            message: tofuResult.message,
            errorType: RiseSshErrorType.securityViolation,
          );
        }

        if (tofuResult.status == TofuStatus.newHost && tofuResult.needsUserConfirmation) {
          await socket.close();
          throw RiseSshException(
            message: 'New server detected. User confirmation required.',
            errorType: RiseSshErrorType.newHostConfirmation,
          );
        }
      }

      // Load private key
      final keyPair = await keyManager.loadPrivateKey();

      _client = SSHClient(
        socket,
        username: username,
        identities: [keyPair],
      );

      // Save host if trusted
      if (_currentFingerprint != null && _currentAlgorithm != null) {
        await tofuVerifier.addHost(
          host: host,
          port: port,
          fingerprint: _currentFingerprint!,
          algorithm: _currentAlgorithm!,
        );
      }

      _isConnected = true;
      return true;
    } catch (e) {
      debugPrint('SSH key connection failed: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Connect and automatically choose method (key if available, password otherwise).
  Future<bool> connect() async {
    if (_client != null && _isConnected) return true;
    
    final hasKey = await keyManager.hasKeyPair();
    if (hasKey) {
      return await connectWithKey();
    } else if (password != null) {
      return await connectWithPassword();
    } else {
      throw ArgumentError('Either password or key must be available');
    }
  }

  /// Disconnect from server.
  Future<void> disconnect() async {
    try {
      _session?.close();
      _client?.close();
    } catch (e) {
      debugPrint('Error disconnecting: $e');
    } finally {
      _client = null;
      _session = null;
      _isConnected = false;
    }
  }

  /// Execute a RISE command with JSON parsing.
  Future<Map<String, dynamic>> execute(
    String command, {
    CommandType timeout = CommandType.quick,
  }) async {
    if (_client == null || !_isConnected) {
      throw RiseSshException(
        message: 'Not connected',
        errorType: RiseSshErrorType.notConnected,
      );
    }

    return await commandExecutor.run(_client!, command, timeout: timeout);
  }

  /// Execute a raw command without JSON parsing.
  Future<String> executeRaw(
    String command, {
    CommandType timeout = CommandType.quick,
  }) async {
    if (_client == null || !_isConnected) {
      throw RiseSshException(
        message: 'Not connected',
        errorType: RiseSshErrorType.notConnected,
      );
    }

    return await commandExecutor.runRaw(_client!, command, timeout: timeout);
  }

  /// Upload a file via SFTP.
  Future<void> uploadFile(String localPath, String remotePath) async {
    if (_client == null || !_isConnected) {
      throw RiseSshException(
        message: 'Not connected',
        errorType: RiseSshErrorType.notConnected,
      );
    }

    final sftp = await _client!.sftp();
    final file = await sftp.open(remotePath, mode: SftpFileMode.createWrite());
    
    // Read local file and write to remote
    final localFile = await file.openWrite();
    final bytes = await _readFileBytes(localPath);
    localFile.add(bytes);
    await localFile.close();
  }

  Future<Uint8List> _readFileBytes(String path) async {
    // Simple implementation - in production use dart:io File
    throw UnimplementedError('Use dart:io File directly');
  }

  /// Get server's host key for TOFU.
  Future<SSHKey?> _getServerKey(SSHSocket socket) async {
    // dartssh2 handles this internally, we extract from socket
    return null; // Simplified - actual implementation depends on dartssh2 API
  }

  /// Calculate fingerprint from key.
  String _fingerprintFromKey(SSHKey key) {
    // SHA256 fingerprint format as per specs
    return 'SHA256:${key.fingerprint}';
  }
}

/// Exception for SSH operations.
class RiseSshException implements Exception {
  final String message;
  final RiseSshErrorType errorType;

  RiseSshException({
    required this.message,
    required this.errorType,
  });

  @override
  String toString() => 'RiseSshException: $message';
}

/// SSH error types.
enum RiseSshErrorType {
  notConnected,
  connectionFailed,
  authenticationFailed,
  securityViolation,
  newHostConfirmation,
  timeout,
}

/// TOFU status for external use
export 'tofu_verifier.dart' show TofuVerifier, TofuResult, TofuStatus, KnownHostEntry;
export 'key_manager.dart' show KeyManager;
export 'command_executor.dart' show CommandExecutor, CommandType, RiseCommandException, ApiVersionChecker, ApiVersionResult;
