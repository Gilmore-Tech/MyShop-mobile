import 'package:flutter/material.dart';

/// Root widget for the MyShop Client App.
/// PRD Reference: Section 4 (Client App)
class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyShop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A73E8), // Placeholder — Phase 6 brand
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('MyShop Client — TODO: Add routing')),
      ),
    );
  }
}
