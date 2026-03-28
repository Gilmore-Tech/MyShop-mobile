import 'package:flutter/material.dart';

/// Profile: name, photo, phone, email, verification status, cancellation rate, rating
/// PRD Reference: PRD 5.4
class ProviderProfileScreen extends StatelessWidget {
  const ProviderProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ProviderProfileScreen')),
      body: const Center(
        child: Text('TODO: Implement ProviderProfileScreen'),
      ),
    );
  }
}
