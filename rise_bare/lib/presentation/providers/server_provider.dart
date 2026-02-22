import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/models/server.dart';
import '../../data/services/ssh_service.dart';
import '../../data/services/storage_service.dart';
import '../../data/services/onboarding_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class ServerProvider extends ChangeNotifier {
  final StorageService _storage = StorageService();
  List<Server> _servers = [];
  Server? _selectedServer;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String? _errorMessage;
  SSHService? _sshService;
  bool _isInitialized = false;

  List<Server> get servers => _servers;
  Server? get selectedServer => _selectedServer;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String? get errorMessage => _errorMessage;
  SSHService? get sshService => _sshService;
  bool get isInitialized => _isInitialized;

  /// Initialize storage and load servers
  Future<void> init() async {
    if (_isInitialized) return;

    await _storage.init();
    await loadServers();
    _isInitialized = true;
  }

  /// Load servers from storage
  Future<void> loadServers() async {
    final data = await _storage.loadServers();
    _servers = data.map((s) => Server.fromJson(s)).toList();
    notifyListeners();
  }

  /// Add a new server and optionally connect to it
  Future<void> addServer(Server server, {bool autoConnect = true}) async {
    _servers.add(server);
    await _saveServers();

    if (autoConnect) {
      await connectToServer(server);
    }

    notifyListeners();
  }

  /// Update a server
  Future<void> updateServer(Server server) async {
    final index = _servers.indexWhere((s) => s.id == server.id);
    if (index != -1) {
      _servers[index] = server;
      await _saveServers();
      notifyListeners();
    }
  }

  /// Remove a server
  Future<void> removeServer(Server server) async {
    if (_selectedServer?.id == server.id) {
      await disconnect();
    }

    _servers.removeWhere((s) => s.id == server.id);
    await _storage.deleteSSHKey(server.id);
    await _saveServers();
    notifyListeners();
  }

  /// Select a server
  void selectServer(Server? server) {
    _selectedServer = server;
    notifyListeners();
  }

  /// Connect to a server via SSH
  Future<bool> connectToServer(Server server) async {
    _connectionStatus = ConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    try {
      // Check if we have SSH key stored
      final privateKey = await _storage.getSSHKey(server.id);

      _sshService = SSHService(
        host: server.host,
        port: server.port,
        username: server.username,
        password: '', // Would use key-based auth
      );

      final connected = await _sshService!.connect();

      if (connected) {
        _connectionStatus = ConnectionStatus.connected;
        _selectedServer = server;
        notifyListeners();
        return true;
      } else {
        _connectionStatus = ConnectionStatus.error;
        _errorMessage = 'Failed to connect to server';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _connectionStatus = ConnectionStatus.error;
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Disconnect from current server
  Future<void> disconnect() async {
    await _sshService?.disconnect();
    _sshService = null;
    _connectionStatus = ConnectionStatus.disconnected;
    notifyListeners();
  }

  /// Onboard a new server
  Future<OnboardingResult> onboardServer({
    required String host,
    required int port,
    required String username,
    required String password,
    required SecurityMode securityMode,
  }) async {
    // Create temporary SSH service for onboarding
    final tempSsh = SSHService(
      host: host,
      port: port,
      username: username,
      password: password,
    );

    // Connect
    final connected = await tempSsh.connect();
    if (!connected) {
      return OnboardingResult(
        success: false,
        error: 'Failed to connect to server',
      );
    }

    // Check if RISE is already installed
    final onboardingService = OnboardingService(tempSsh);
    final checkResult = await onboardingService.checkExistingInstallation();

    // Generate SSH key pair for this device
    // Note: In real implementation, we'd store the private key securely

    OnboardingResult result;

    if (checkResult.status == OnboardingStatus.notInstalled) {
      // Install RISE
      result = await onboardingService.installRISE(
        securityMode: securityMode.name,
        publicKey: 'generated-public-key', // Would use real public key
      );
    } else {
      // Add this device to existing installation
      result = await onboardingService.addDeviceToExistingServer(
        'generated-public-key', // Would use real public key
      );
    }

    // Cleanup
    await tempSsh.disconnect();

    if (result.success) {
      // Save server to storage
      final server = Server(
        id: const Uuid().v4(),
        name: host,
        host: host,
        port: port,
        username: username,
        securityMode: securityMode,
      );

      await addServer(server);
    }

    return result;
  }

  /// Run health check on current server
  Future<Map<String, dynamic>?> runHealthCheck() async {
    if (_sshService == null || !_sshService!.isConnected) {
      return null;
    }

    return await _sshService!.runHealthCheck();
  }

  /// Run firewall command
  Future<SSHResult> runFirewallCommand(String subcommand, [String? args]) async {
    if (_sshService == null || !_sshService!.isConnected) {
      return SSHResult(success: false, output: '', exitCode: -1);
    }

    return await _sshService!.runFirewallCommand(subcommand, args);
  }

  /// Run docker command
  Future<SSHResult> runDockerCommand(String subcommand, [String? args]) async {
    if (_sshService == null || !_sshService!.isConnected) {
      return SSHResult(success: false, output: '', exitCode: -1);
    }

    return await _sshService!.runDockerCommand(subcommand, args);
  }

  /// Run update command
  Future<SSHResult> runUpdateCommand(String subcommand, [String? args]) async {
    if (_sshService == null || !_sshService!.isConnected) {
      return SSHResult(success: false, output: '', exitCode: -1);
    }

    return await _sshService!.runUpdateCommand(subcommand, args);
  }

  void setError(String message) {
    _connectionStatus = ConnectionStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  Future<void> _saveServers() async {
    await _storage.saveServers(_servers.map((s) => s.toJson()).toList());
  }
}
