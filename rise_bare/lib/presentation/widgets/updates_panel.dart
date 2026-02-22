import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/server_provider.dart';

class UpdatesPanel extends StatefulWidget {
  const UpdatesPanel({super.key});

  @override
  State<UpdatesPanel> createState() => _UpdatesPanelState();
}

class _UpdatesPanelState extends State<UpdatesPanel> {
  bool _isLoading = false;
  bool _upToDate = false;
  int _securityCount = 0;
  int _normalCount = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkUpdates();
  }

  Future<void> _checkUpdates() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final serverProvider = context.read<ServerProvider>();
    final result = await serverProvider.runUpdateCommand('check');

    if (result.success) {
      final output = result.output.toLowerCase();
      setState(() {
        _upToDate = output.contains('up to date') || output.contains('0 packages');
        _securityCount = _parseCount(output, 'security');
        _normalCount = _parseCount(output, 'upgrade');
      });
    } else {
      setState(() {
        _error = result.error;
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  int _parseCount(String output, String type) {
    final regex = RegExp('(\\d+)\\s+$type');
    final match = regex.firstMatch(output);
    return match != null ? int.tryParse(match.group(1) ?? '0') ?? 0 : 0;
  }

  Future<void> _installUpdates() async {
    setState(() {
      _isLoading = true;
    });

    final serverProvider = context.read<ServerProvider>();
    final result = await serverProvider.runUpdateCommand('install');

    setState(() {
      _isLoading = false;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Updates installed successfully')),
        );
        _checkUpdates();
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _installSecurityOnly() async {
    setState(() {
      _isLoading = true;
    });

    final serverProvider = context.read<ServerProvider>();
    final result = await serverProvider.runUpdateCommand('security');

    setState(() {
      _isLoading = false;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Security updates installed')),
        );
        _checkUpdates();
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _checkUpdates,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    _isLoading
                        ? Icons.sync
                        : _upToDate
                            ? Icons.check_circle
                            : Icons.system_update,
                    size: 48,
                    color: _upToDate ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isLoading
                        ? 'Checking for updates...'
                        : _upToDate
                            ? 'System is up to date'
                            : 'Updates Available',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!_upToDate && !_isLoading) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_securityCount > 0)
                          _buildUpdateBadge(
                            '$_securityCount Security',
                            Colors.red,
                          ),
                        if (_securityCount > 0 && _normalCount > 0)
                          const SizedBox(width: 8),
                        if (_normalCount > 0)
                          _buildUpdateBadge(
                            '$_normalCount Regular',
                            Colors.orange,
                          ),
                      ],
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Actions
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isLoading || _upToDate ? null : _installUpdates,
                  icon: const Icon(Icons.download),
                  label: const Text('Install All'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading || _securityCount == 0 ? null : _installSecurityOnly,
                  icon: const Icon(Icons.security),
                  label: const Text('Security Only'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Last check info
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Last checked'),
              subtitle: const Text('Pull to refresh'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _checkUpdates,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
