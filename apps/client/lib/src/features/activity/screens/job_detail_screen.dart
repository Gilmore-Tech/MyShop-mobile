import 'package:flutter/material.dart';

/// Job history detail: description, artisan info, bid amount, supplement (if any), rating, payment receipt
/// PRD Reference: PRD 4.6
class JobDetailScreen extends StatelessWidget {
  const JobDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JobDetailScreen')),
      body: const Center(
        child: Text('TODO: Implement JobDetailScreen'),
      ),
    );
  }
}
