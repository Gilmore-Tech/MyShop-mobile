import 'package:flutter/material.dart';

/// Live artisan tracking, ETA, chat/call, share link, emergency button. Status: en_route → arrived → in_progress
/// PRD Reference: PRD 4.6
class JobTrackingScreen extends StatelessWidget {
  const JobTrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JobTrackingScreen')),
      body: const Center(
        child: Text('TODO: Implement JobTrackingScreen'),
      ),
    );
  }
}
