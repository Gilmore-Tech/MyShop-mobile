import 'package:flutter/material.dart';

/// Root widget for the MyShop Provider App.
/// PRD Reference: Section 5 (Provider App)
class ProviderApp extends StatelessWidget {
  const ProviderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyShop Provider',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF1A73E8), // Placeholder — Phase 6 brand
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('MyShop Provider — TODO: Add routing')),
      ),
    );
  }
}
