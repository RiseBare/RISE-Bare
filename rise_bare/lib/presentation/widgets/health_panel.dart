import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/server_provider.dart';

class HealthPanel extends StatefulWidget {
  const HealthPanel({super.key});

  @override
  State<HealthPanel> createState() => _HealthPanelState();
}

class _HealthPanelState extends State<HealthPanel> {
  bool _isLoading = false;
  Map<String, String> _healthChecks = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _runHealthCheck();
  }

  Future<void> _runHealthCheck() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final serverProvider = context.read<ServerProvider>();
    final result = await serverProvider.runHealthCheck();

    if (result != null) {
      setState(() {
        _healthChecks = result.map((k, v) => MapEntry(k, v.toString()));
      });
    } else {
      setState(() {
        _error = 'Failed to run health check';
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _runHealthCheck,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Run health check button
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.health_and_safety, size: 48),
                  const SizedBox(height: 16),
                  const Text('Server Health Check'),
                  const SizedBox(height: 8),
                  Text(
                    'Verify SSH configuration, sudoers, nftables, and scripts',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _runHealthCheck,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: Text(_isLoading ? 'Running...' : 'Run Health Check'),
                  ),
                ],
              ),
            ),
          ),

          if (_error != null)
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

          const SizedBox(height: 16),

          // Health check results
          if (_healthChecks.isNotEmpty) ...[
            Text(
              'Results',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ..._healthChecks.entries.map((entry) => _buildHealthItem(entry.key, entry.value)),
          ],
        ],
      ),
    );
  }

  Widget _buildHealthItem(String key, String value) {
    final isPassed = value.toLowerCase().contains('ok') ||
        value.toLowerCase().contains('passed') ||
        value.toLowerCase().contains('success');

    final isWarning = value.toLowerCase().contains('warning');

    Color statusColor;
    IconData statusIcon;

    if (isPassed) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (isWarning) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
    } else {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text(_formatKey(key)),
        subtitle: Text(value),
        trailing: Icon(
          isPassed ? Icons.thumb_up : Icons.thumb_down,
          color: statusColor,
        ),
      ),
    );
  }

  String _formatKey(String key) {
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty
            ? '${word[0].toUpperCase()}${word.substring(1)}'
            : '')
        .join(' ');
  }
}
