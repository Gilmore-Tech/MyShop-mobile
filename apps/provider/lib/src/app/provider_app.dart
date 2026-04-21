import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../core/services/fcm_service.dart';
import 'router.dart';

/// Root widget for the MyShop Provider App.
/// PRD Reference: Section 5 (Provider App)
class ProviderApp extends ConsumerWidget {
  const ProviderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    // Activate the FCM-tap → GoRouter bridge now that the router exists.
    ref.watch(fcmTapBridgeProvider);

    return MaterialApp.router(
      title: 'MyShop Provider',
      debugShowCheckedModeBanner: false,
      theme: MyShopTheme.light,
      routerConfig: router,
    );
  }
}
