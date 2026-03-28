import 'package:flutter/material.dart';

/// Submit material cost supplement: additional amount + reason. One per job max. Before starting work only
/// PRD Reference: PRD 5.3, 4.5.3
class SupplementRequestScreen extends StatelessWidget {
  const SupplementRequestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SupplementRequestScreen')),
      body: const Center(
        child: Text('TODO: Implement SupplementRequestScreen'),
      ),
    );
  }
}
