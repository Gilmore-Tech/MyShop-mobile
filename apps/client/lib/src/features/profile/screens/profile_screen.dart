import 'package:flutter/material.dart';

/// Profile tab: name, photo, email, phone, loyalty points summary, settings list
/// PRD Reference: PRD 4.9, 4.11
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ProfileScreen')),
      body: const Center(
        child: Text('TODO: Implement ProfileScreen'),
      ),
    );
  }
}
