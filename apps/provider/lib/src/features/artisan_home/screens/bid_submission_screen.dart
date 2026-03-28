import 'package:flutter/material.dart';

/// Submit bid: amount (validated against category minimum), optional message to client
/// PRD Reference: PRD 5.3
class BidSubmissionScreen extends StatelessWidget {
  const BidSubmissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BidSubmissionScreen')),
      body: const Center(
        child: Text('TODO: Implement BidSubmissionScreen'),
      ),
    );
  }
}
