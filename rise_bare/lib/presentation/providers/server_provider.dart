import 'package:flutter/material.dart';
import '../../data/models/server.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class ServerProvider extends ChangeNotifier {
  List<Server> _servers = [];
  Server? _selectedServer;
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  String? _errorMessage;

  List<Server> get servers => _servers;
  Server? get selectedServer => _selectedServer;
  ConnectionStatus get connectionStatus => _connectionStatus;
  String? get errorMessage => _errorMessage;

  void addServer(Server server) {
    _servers.add(server);
    notifyListeners();
  }

  void removeServer(Server server) {
    _servers.remove(server);
    if (_selectedServer == server) {
      _selectedServer = null;
    }
    notifyListeners();
  }

  void selectServer(Server? server) {
    _selectedServer = server;
    notifyListeners();
  }

  Future<void> connectToServer(Server server) async {
    _connectionStatus = ConnectionStatus.connecting;
    _errorMessage = null;
    notifyListeners();

    // TODO: Implement actual SSH connection
    // For now, simulate connection
    await Future.delayed(const Duration(seconds: 2));

    _connectionStatus = ConnectionStatus.connected;
    _selectedServer = server;
    notifyListeners();
  }

  void disconnect() {
    _connectionStatus = ConnectionStatus.disconnected;
    _selectedServer = null;
    notifyListeners();
  }

  void setError(String message) {
    _connectionStatus = ConnectionStatus.error;
    _errorMessage = message;
    notifyListeners();
  }
}
