import 'package:flutter/material.dart';

/// First screen: choose Driver or Artisan. Role permanently locked after selection
/// PRD Reference: PRD 5.1
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RoleSelectionScreen')),
      body: const Center(
        child: Text('TODO: Implement RoleSelectionScreen'),
      ),
    );
  }
}
