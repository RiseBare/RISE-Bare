import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/server_provider.dart';

class DockerPanel extends StatefulWidget {
  const DockerPanel({super.key});

  @override
  State<DockerPanel> createState() => _DockerPanelState();
}

class _DockerPanelState extends State<DockerPanel> {
  bool _isLoading = false;
  List<DockerContainer> _containers = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContainers();
  }

  Future<void> _loadContainers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final serverProvider = context.read<ServerProvider>();
    final result = await serverProvider.runDockerCommand('list');

    if (result.success) {
      final lines = result.output.split('\n').skip(1).toList(); // Skip header
      final containers = <DockerContainer>[];

      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          containers.add(DockerContainer(
            id: parts[0],
            name: parts[1],
            status: parts[2],
            image: parts.sublist(3).join(' '),
          ));
        }
      }

      setState(() {
        _containers = containers;
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

  Future<void> _startContainer(String containerId) async {
    setState(() => _isLoading = true);

    final serverProvider = context.read<ServerProvider>();
    await serverProvider.runDockerCommand('start', containerId);

    await _loadContainers();
  }

  Future<void> _stopContainer(String containerId) async {
    setState(() => _isLoading = true);

    final serverProvider = context.read<ServerProvider>();
    await serverProvider.runDockerCommand('stop', containerId);

    await _loadContainers();
  }

  Future<void> _restartContainer(String containerId) async {
    setState(() => _isLoading = true);

    final serverProvider = context.read<ServerProvider>();
    await serverProvider.runDockerCommand('restart', containerId);

    await _loadContainers();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadContainers,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header with refresh
          Row(
            children: [
              Text(
                'Docker Containers',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _isLoading ? null : _loadContainers,
              ),
            ],
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

          if (_isLoading && _containers.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_containers.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No Docker containers found'),
                    Text('Install Docker on your server to manage containers', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            ..._containers.map((container) => _buildContainerCard(container)),
        ],
      ),
    );
  }

  Widget _buildContainerCard(DockerContainer container) {
    final isRunning = container.status.toLowerCase().contains('up');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isRunning ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        container.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        container.image,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  container.status,
                  style: TextStyle(
                    fontSize: 12,
                    color: isRunning ? Colors.green : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isRunning)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _startContainer(container.id),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Start'),
                    ),
                  )
                else ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _stopContainer(container.id),
                      icon: const Icon(Icons.stop, size: 18),
                      label: const Text('Stop'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : () => _restartContainer(container.id),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Restart'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DockerContainer {
  final String id;
  final String name;
  final String status;
  final String image;

  DockerContainer({
    required this.id,
    required this.name,
    required this.status,
    required this.image,
  });
}
