import 'package:flutter/material.dart';

/// Saved payment methods: MoMo (MTN/Telecel/AirtelTigo), Visa/MC. Set preferred
/// PRD Reference: PRD 4.8
class PaymentMethodsScreen extends StatelessWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PaymentMethodsScreen')),
      body: const Center(
        child: Text('TODO: Implement PaymentMethodsScreen'),
      ),
    );
  }
}
