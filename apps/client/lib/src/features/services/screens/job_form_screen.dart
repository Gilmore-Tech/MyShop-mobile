import 'package:flutter/material.dart';

/// Job request form: category, description, photos, location (Mapbox pin-drop), preferred time (immediate/scheduled)
/// PRD Reference: PRD 4.5
class JobFormScreen extends StatelessWidget {
  const JobFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JobFormScreen')),
      body: const Center(
        child: Text('TODO: Implement JobFormScreen'),
      ),
    );
  }
}
