import 'package:flutter/material.dart';

/// Full-screen incoming ride notification: pickup location, distance, estimated earnings. Accept/decline within 15s
/// PRD Reference: PRD 5.2
class RideRequestScreen extends StatelessWidget {
  const RideRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RideRequestScreen')),
      body: const Center(
        child: Text('TODO: Implement RideRequestScreen'),
      ),
    );
  }
}
