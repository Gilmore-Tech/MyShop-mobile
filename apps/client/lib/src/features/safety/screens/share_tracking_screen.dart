import 'package:flutter/material.dart';

/// Share live tracking link with trusted contacts. Expires after booking + 30 min buffer
/// PRD Reference: PRD 4.6, 9.3
class ShareTrackingScreen extends StatelessWidget {
  const ShareTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ShareTrackingScreen')),
      body: const Center(
        child: Text('TODO: Implement ShareTrackingScreen'),
      ),
    );
  }
}
