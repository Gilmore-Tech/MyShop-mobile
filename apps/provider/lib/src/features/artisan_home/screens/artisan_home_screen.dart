import 'package:flutter/material.dart';

/// Online/offline toggle, active jobs count, concurrent job slots, earnings summary
/// PRD Reference: PRD 5.3
class ArtisanHomeScreen extends StatelessWidget {
  const ArtisanHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ArtisanHomeScreen')),
      body: const Center(
        child: Text('TODO: Implement ArtisanHomeScreen'),
      ),
    );
  }
}
