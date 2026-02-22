import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/server.dart';
import '../providers/server_provider.dart';

class SecurityPanel extends StatefulWidget {
  const SecurityPanel({super.key});

  @override
  State<SecurityPanel> createState() => _SecurityPanelState();
}

class _SecurityPanelState extends State<SecurityPanel> {
  bool _isLoading = false;
  List<SSHKey> _keys = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // TODO: Implement SSH key listing via SSH command
    // For now, simulate with empty list
    await Future.delayed(const Duration(seconds: 1));

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _addNewDevice() async {
    // TODO: Generate OTP or show instructions for adding new device
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Device'),
        content: const Text(
          'To add a new device:\n\n'
          '1. Open RISE Bare on the new device\n'
          '2. Click "Add Server"\n'
          '3. Select "RISE OTP" tab\n'
          '4. Enter this server\'s IP and the OTP code shown on the other device',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeKey(SSHKey key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke SSH Key'),
        content: Text('Are you sure you want to revoke access for "${key.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // TODO: Implement key revocation via SSH command
    setState(() {
      _keys.removeWhere((k) => k.id == key.id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('SSH key revoked')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final server = serverProvider.selectedServer;

    return RefreshIndicator(
      onRefresh: _loadKeys,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Security Mode Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.security),
                      const SizedBox(width: 8),
                      Text(
                        'Security Mode',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSecurityModeInfo(server?.securityMode ?? SecurityMode.mode3),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // SSH Keys Section
          Row(
            children: [
              Text(
                'Registered Devices',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _addNewDevice,
                icon: const Icon(Icons.add),
                label: const Text('Add Device'),
              ),
            ],
          ),

          const SizedBox(height: 8),

          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_keys.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(Icons.key_off, size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    const Text('No additional devices registered'),
                    const SizedBox(height: 8),
                    Text(
                      'Add other devices to manage this server',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._keys.map((key) => _buildKeyCard(key)),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.error, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecurityModeInfo(SecurityMode mode) {
    String title;
    String description;
    Color color;
    IconData icon;

    switch (mode) {
      case SecurityMode.mode1:
        title = 'Mode 1: Password for all';
        description = 'All users can connect with password. Not recommended for production.';
        color = Colors.red;
        icon = Icons.lock_open;
        break;
      case SecurityMode.mode2:
        title = 'Mode 2: Root key only, others password';
        description = 'Administrative accounts use SSH key. Other users can use password.';
        color = Colors.orange;
        icon = Icons.lock;
        break;
      case SecurityMode.mode3:
        title = 'Mode 3: SSH Key only (Recommended)';
        description = 'All users must use SSH keys. Maximum security.';
        color = Colors.green;
        icon = Icons.lock;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyCard(SSHKey key) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          child: Text(key.name[0].toUpperCase()),
        ),
        title: Text(key.name),
        subtitle: Text(
          'Added ${key.addedAt}',
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.outline,
          ),
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () => _revokeKey(key),
        ),
      ),
    );
  }
}

class SSHKey {
  final String id;
  final String name;
  final String fingerprint;
  final String addedAt;

  SSHKey({
    required this.id,
    required this.name,
    required this.fingerprint,
    required this.addedAt,
  });
}
