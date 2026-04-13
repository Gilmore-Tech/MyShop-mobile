import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme_provider.dart';

/// Root widget for the MyShop Client App.
/// Wraps the app with [ProviderScope] for Riverpod state management.
/// PRD Reference: Section 4 (Client App)
class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const ProviderScope(
      child: _MyShopMaterialApp(),
    );
  }
}

class _MyShopMaterialApp extends ConsumerWidget {
  const _MyShopMaterialApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeNotifierProvider);
    final router    = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'MyShop',
      debugShowCheckedModeBanner: false,
      theme: MyShopTheme.light,
      darkTheme: MyShopTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}

// ── Theme Definitions ─────────────────────────────────────────────────────────
// Uses MyShop brand colours from CLAUDE.md § 5.2.
// colorSchemeSeed drives Material 3 tonal palette generation.

abstract final class MyShopTheme {
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        colorSchemeSeed: const Color(0xFFF5A623), // primaryGold
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F8), // offWhite
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Color(0xFF161A1D), // darkText
        ),
        splashFactory: InkRipple.splashFactory,
      );

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFF5A623), // primaryGold
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A1A),
          elevation: 0,
          scrolledUnderElevation: 0,
          foregroundColor: Colors.white,
        ),
        splashFactory: InkRipple.splashFactory,
      );
}
