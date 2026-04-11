import 'package:flutter/material.dart';
import 'package:myshop_client/src/features/home/screens/home_screen.dart';
import 'package:myshop_client/src/features/ride/screens/destination_search_screen.dart';
import 'package:myshop_client/src/features/ride/screens/driver_matching_screen.dart';

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
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const HomeScreen(),
                    ),
                  );
                },
                child: const Text('Press Me'),
              );
            }
          ),
        ),
      ),
    );
  }
}
