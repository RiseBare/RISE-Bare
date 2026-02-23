import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Manages Ed25519 key pair generation and storage for SSH authentication.
/// Uses flutter_secure_storage for private key storage.
class KeyManager {
  static const String _privateKeyKey = 'rise_ed25519_private_key';
  static const String _publicKeyKey = 'rise_ed25519_public_key';
  static const String _keyIdKey = 'rise_key_id';

  final FlutterSecureStorage _secureStorage;
  final Uuid _uuid;

  String? _cachedPublicKey;
  String? _cachedPrivateKeyPem;

  KeyManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
        ),
        _uuid = const Uuid();

  /// Ensures an Ed25519 key pair exists, generating one if necessary.
  Future<void> ensureKeyPair() async {
    final existingPrivateKey = await _secureStorage.read(key: _privateKeyKey);
    final existingPublicKey = await _secureStorage.read(key: _publicKeyKey);

    if (existingPrivateKey != null && existingPublicKey != null) {
      _cachedPrivateKeyPem = existingPrivateKey;
      _cachedPublicKey = existingPublicKey;
      return;
    }

    // Generate new Ed25519 key pair using ssh-keygen for proper PEM format
    final keyPair = await _generateEd25519KeyPairWithSshKeygen();
    
    // Store key ID
    final keyId = _uuid.v4();
    await _secureStorage.write(key: _keyIdKey, value: keyId);

    // Store keys (PEM format for private key, string for public key)
    await _secureStorage.write(
      key: _privateKeyKey,
      value: keyPair.privateKeyPem,
    );
    await _secureStorage.write(
      key: _publicKeyKey,
      value: keyPair.publicKey,
    );

    _cachedPrivateKeyPem = keyPair.privateKeyPem;
    _cachedPublicKey = keyPair.publicKey;
  }

  /// Returns the public key formatted for authorized_keys.
  Future<String> getPublicKeyString() async {
    if (_cachedPublicKey == null) {
      await ensureKeyPair();
    }
    return _cachedPublicKey!;
  }

  /// Loads the private key for use with dartssh2.
  Future<SSHKeyPair> loadPrivateKey() async {
    if (_cachedPrivateKeyPem == null) {
      await ensureKeyPair();
    }

    final keyPair = SSHKeyPair.fromPem(
      _cachedPrivateKeyPem!,
      null, // No passphrase for generated keys
    );

    return keyPair.first;
  }

  /// Checks if a key pair exists.
  Future<bool> hasKeyPair() async {
    final privateKey = await _secureStorage.read(key: _privateKeyKey);
    return privateKey != null;
  }

  /// Gets the key ID if it exists.
  Future<String?> getKeyId() async {
    return await _secureStorage.read(key: _keyIdKey);
  }

  /// Deletes the key pair (for testing/reset purposes).
  Future<void> deleteKeyPair() async {
    await _secureStorage.delete(key: _privateKeyKey);
    await _secureStorage.delete(key: _publicKeyKey);
    await _secureStorage.delete(key: _keyIdKey);
    _cachedPrivateKeyPem = null;
    _cachedPublicKey = null;
  }
}

/// Generates an Ed25519 key pair using ssh-keygen for proper PEM format.
Future<_KeyPairData> _generateEd25519KeyPairWithSshKeygen() async {
  // Create a temporary directory for key generation
  final tempDir = Directory.systemTemp.createTempSync('rise_ssh_key_');
  final privateKeyPath = '${tempDir.path}/id_ed25519';
  final publicKeyPath = '$privateKeyPath.pub';

  try {
    // Generate Ed25519 key with ssh-keygen
    final result = await Process.run(
      'ssh-keygen',
      [
        '-t', 'ed25519',
        '-f', privateKeyPath,
        '-N', '', // No passphrase
        '-C', 'rise@device', // Comment
      ],
    );

    if (result.exitCode != 0) {
      throw Exception('ssh-keygen failed: ${result.stderr}');
    }

    // Read the generated private key (PEM format)
    final privateKeyPem = await File(privateKeyPath).readAsString();

    // Read the generated public key
    final publicKey = (await File(publicKeyPath).readAsString()).trim();

    return _KeyPairData(
      privateKeyPem: privateKeyPem,
      publicKey: publicKey,
    );
  } finally {
    // Clean up temp files
    try {
      await File(privateKeyPath).delete();
      await File(publicKeyPath).delete();
      await tempDir.delete();
    } catch (_) {
      // Ignore cleanup errors
    }
  }
}

class _KeyPairData {
  final String privateKeyPem;
  final String publicKey;

  _KeyPairData({required this.privateKeyPem, required this.publicKey});
}

/// Result from key generation
class KeyGenerationResult {
  final String publicKey;
  final String keyId;
  final bool wasGenerated;

  KeyGenerationResult({
    required this.publicKey,
    required this.keyId,
    required this.wasGenerated,
  });
}
