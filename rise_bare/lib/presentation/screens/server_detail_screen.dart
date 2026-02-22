import 'package:flutter/material.dart';

class ServerDetailScreen extends StatelessWidget {
  const ServerDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Details'),
      ),
      body: const Center(
        child: Text('Select a server to view details'),
      ),
    );
  }
}
