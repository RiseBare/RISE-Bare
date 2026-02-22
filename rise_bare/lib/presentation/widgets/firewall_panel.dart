import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/server_provider.dart';

class FirewallPanel extends StatefulWidget {
  const FirewallPanel({super.key});

  @override
  State<FirewallPanel> createState() => _FirewallPanelState();
}

class _FirewallPanelState extends State<FirewallPanel> {
  bool _isLoading = false;
  String? _status;
  List<String> _rules = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final serverProvider = context.read<ServerProvider>();
    final result = await serverProvider.runFirewallCommand('status');

    if (result.success) {
      setState(() {
        _status = result.output.trim();
        _rules = result.output.split('\n').where((r) => r.isNotEmpty).toList();
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

  Future<void> _applyRules() async {
    setState(() {
      _isLoading = true;
    });

    final serverProvider = context.read<ServerProvider>();
    final result = await serverProvider.runFirewallCommand('apply');

    setState(() {
      _isLoading = false;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rules applied successfully')),
        );
      } else {
        _error = result.error;
      }
    });
  }

  Future<void> _rollbackRules() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rollback Rules'),
        content: const Text('Are you sure you want to rollback the firewall rules?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Rollback'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    final serverProvider = context.read<ServerProvider>();
    final result = await serverProvider.runFirewallCommand('rollback');

    setState(() {
      _isLoading = false;
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rules rolled back')),
        );
        _loadStatus();
      } else {
        _error = result.error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadStatus,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.shield,
                        color: _status == 'active' ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Firewall Status',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (_isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status ?? 'Unknown',
                    style: TextStyle(
                      color: _status == 'active' ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
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
                  onPressed: _isLoading ? null : _applyRules,
                  icon: const Icon(Icons.check),
                  label: const Text('Apply Rules'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : _rollbackRules,
                  icon: const Icon(Icons.undo),
                  label: const Text('Rollback'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Rules list
          Text(
            'Current Rules',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),

          if (_rules.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No rules configured'),
              ),
            )
          else
            Card(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _rules.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final rule = _rules[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.rule, size: 20),
                    title: Text(rule),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
