import 'package:flutter/material.dart';

/// App launch — MyShop logo, auto-login check
/// PRD Reference: PRD 4.1
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SplashScreen')),
      body: const Center(
        child: Text('TODO: Implement SplashScreen'),
      ),
    );
  }
}
