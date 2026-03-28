import 'package:flutter/material.dart';

/// Payout preference: instant vs end-of-day batch. Payout method: MoMo or bank. Account number
/// PRD Reference: PRD 5.5
class PayoutSettingsScreen extends StatelessWidget {
  const PayoutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PayoutSettingsScreen')),
      body: const Center(
        child: Text('TODO: Implement PayoutSettingsScreen'),
      ),
    );
  }
}
