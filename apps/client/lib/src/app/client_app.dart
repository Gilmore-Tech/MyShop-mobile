import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import 'router.dart';
import 'theme_provider.dart';

/// Root widget for the MyShop Client App.
/// PRD Reference: Section 4 (Client App)
class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _MyShopMaterialApp();
  }
}

class _MyShopMaterialApp extends ConsumerWidget {
  const _MyShopMaterialApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeNotifierProvider);

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
