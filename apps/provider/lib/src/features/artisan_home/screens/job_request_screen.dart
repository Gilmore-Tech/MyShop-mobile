import 'package:flutter/material.dart';

/// Incoming job notification: category, description, photos, client location. 5-minute bid window
/// PRD Reference: PRD 5.3
class JobRequestScreen extends StatelessWidget {
  const JobRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JobRequestScreen')),
      body: const Center(
        child: Text('TODO: Implement JobRequestScreen'),
      ),
    );
  }
}
