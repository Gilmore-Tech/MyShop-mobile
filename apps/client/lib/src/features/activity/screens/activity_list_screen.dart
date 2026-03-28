import 'package:flutter/material.dart';

/// Tabbed list: Rides | Jobs. Each with status badge, date, amount. Tap for detail
/// PRD Reference: PRD 4.6
class ActivityListScreen extends StatelessWidget {
  const ActivityListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ActivityListScreen')),
      body: const Center(
        child: Text('TODO: Implement ActivityListScreen'),
      ),
    );
  }
}
