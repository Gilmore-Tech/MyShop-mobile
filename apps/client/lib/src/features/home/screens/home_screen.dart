import 'package:flutter/material.dart';

/// Full-screen Google Map with ride search bar, bottom nav (Home|Services|Activity|Profile), floating mini-card for active bookings
/// PRD Reference: PRD 4.2
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HomeScreen')),
      body: const Center(
        child: Text('TODO: Implement HomeScreen'),
      ),
    );
  }
}
