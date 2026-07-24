import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import 'router.dart';
import 'theme_provider.dart';
import '../core/providers/app_lifecycle_provider.dart';
import '../core/providers/app_update_provider.dart';
import '../core/providers/provider_location_notice_provider.dart';
import '../core/providers/socket_provider.dart';
import '../core/widgets/provider_location_notice_banner.dart';
import '../core/di/providers.dart' show systemTelemetryProvider;

/// Root widget for the MyShop Client App.
/// PRD Reference: Section 4 (Client App)
class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const _MyShopMaterialApp();
  }
}

class _MyShopMaterialApp extends ConsumerStatefulWidget {
  const _MyShopMaterialApp();

  @override
  ConsumerState<_MyShopMaterialApp> createState() => _MyShopMaterialAppState();
}

class _MyShopMaterialAppState extends ConsumerState<_MyShopMaterialApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foregrounded = isForegroundLifecycleState(state);
    ref.read(appForegroundedProvider.notifier).state = foregrounded;
    if (foregrounded) {
      // Push is the background reachability channel. Recreate the general
      // ride/job socket only when visible; SocketService reattaches all
      // handlers through onAfterCreate before the connection opens.
      unawaited(ref.read(socketServiceProvider).connect());
    } else {
      // Do not retain an idle client WebSocket for every backgrounded DAU.
      // In-app calls use their separate call socket and are unaffected.
      ref.read(socketServiceProvider).disconnect();
    }
    ref.read(systemTelemetryProvider).trackLifecycle(state);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeNotifierProvider);
    final updateRequirement = ref.watch(appUpdateRequirementProvider);
    final providerLocationNotice = ref.watch(providerLocationNoticeProvider);

    return MaterialApp.router(
      title: 'MyShop',
      debugShowCheckedModeBanner: false,
      theme: MyShopTheme.light,
      darkTheme: MyShopTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        if (updateRequirement != null) {
          return MandatoryAppUpdateScreen(
            message: updateRequirement.message,
            storeUrl: updateRequirement.storeUrl,
          );
        }
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            if (providerLocationNotice != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ProviderLocationNoticeBanner(
                  notice: providerLocationNotice,
                ),
              ),
          ],
        );
      },
    );
  }
}
