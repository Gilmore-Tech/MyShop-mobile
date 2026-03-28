import 'package:flutter/material.dart';

/// For dual-role users (driver+artisan): pick which dashboard to enter at login
/// PRD Reference: PRD 3.1
class RolePickerScreen extends StatelessWidget {
  const RolePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RolePickerScreen')),
      body: const Center(
        child: Text('TODO: Implement RolePickerScreen'),
      ),
    );
  }
}
