import 'package:flutter/material.dart';

/// Average rating, individual review history with comments. Warning banner if below 3.5
/// PRD Reference: PRD 5.3
class RatingsScreen extends StatelessWidget {
  const RatingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RatingsScreen')),
      body: const Center(
        child: Text('TODO: Implement RatingsScreen'),
      ),
    );
  }
}
