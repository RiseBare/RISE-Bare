import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/server_provider.dart';
import '../widgets/firewall_panel.dart';
import '../widgets/docker_panel.dart';
import '../widgets/updates_panel.dart';
import '../widgets/health_panel.dart';
import '../widgets/security_panel.dart';

class ServerDetailScreen extends StatefulWidget {
  const ServerDetailScreen({super.key});

  @override
  State<ServerDetailScreen> createState() => _ServerDetailScreenState();
}

class _ServerDetailScreenState extends State<ServerDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ServerProvider>(
      builder: (context, serverProvider, _) {
        final server = serverProvider.selectedServer;
        final isConnected = serverProvider.connectionStatus == ConnectionStatus.connected;

        if (server == null) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Server Details'),
            ),
            body: const Center(
              child: Text('Select a server to view details'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(server.name),
            bottom: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.shield), text: 'Firewall'),
                Tab(icon: Icon(Icons.cloud), text: 'Docker'),
                Tab(icon: Icon(Icons.system_update), text: 'Updates'),
                Tab(icon: Icon(Icons.health_and_safety), text: 'Health'),
                Tab(icon: Icon(Icons.security), text: 'Security'),
              ],
            ),
            actions: [
              if (!isConnected)
                IconButton(
                  icon: const Icon(Icons.link),
                  tooltip: 'Connect',
                  onPressed: () => serverProvider.connectToServer(server),
                )
              else
                IconButton(
                  icon: const Icon(Icons.link_off),
                  tooltip: 'Disconnect',
                  onPressed: () => serverProvider.disconnect(),
                ),
            ],
          ),
          body: Column(
            children: [
              // Connection status bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: isConnected
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Icon(
                      isConnected ? Icons.cloud_done : Icons.cloud_off,
                      size: 16,
                      color: isConnected ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${server.host}:${server.port}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const Spacer(),
                    Text(
                      isConnected ? 'Connected' : 'Disconnected',
                      style: TextStyle(
                        color: isConnected ? Colors.green : Colors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Tab content
              Expanded(
                child: isConnected
                    ? TabBarView(
                        controller: _tabController,
                        children: const [
                          FirewallPanel(),
                          DockerPanel(),
                          UpdatesPanel(),
                          HealthPanel(),
                          SecurityPanel(),
                        ],
                      )
                    : const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.link_off, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text('Connect to server to view details'),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
