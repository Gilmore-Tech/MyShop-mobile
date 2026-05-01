import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../core/providers/provider_status_provider.dart';
import '../core/providers/socket_provider.dart';
import '../core/services/fcm_service.dart';
import '../features/artisan_jobs/providers/artisan_jobs_provider.dart';
import '../features/auth/providers/auth_controller.dart';
import 'router.dart';

/// Root widget for the MyShop Provider App.
/// PRD Reference: Section 5 (Provider App)
class ProviderApp extends ConsumerStatefulWidget {
  const ProviderApp({super.key});

  @override
  ConsumerState<ProviderApp> createState() => _ProviderAppState();
}

class _ProviderAppState extends ConsumerState<ProviderApp>
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
    switch (state) {
      case AppLifecycleState.resumed:
        // If the session TTL elapsed while the app was backgrounded, boot
        // the user out now rather than waiting for the next 401. The
        // interceptor's proactive expiry check covers access-token expiry
        // mid-session; this covers the outer session window.
        ref.read(authControllerProvider.notifier).recheckSessionOnResume();
        // Restart the artisan-jobs poll + silent reload to catch up on
        // anything FCM didn't deliver while we were paused.
        if (ref.exists(artisanJobsProvider)) {
          ref.read(artisanJobsProvider.notifier).resumePolling();
        }
        // If the user is online, reconnect the socket so the real-time
        // channel is back. (Disconnect-on-pause + reconnect-on-resume is
        // why we don't bleed memory in the background — FCM is the real
        // wakeup channel; the socket is only useful while foreground.)
        final status = ref.read(providerStatusProvider);
        if (status != DriverStatus.offline) {
          ref.read(socketServiceProvider).connect();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Stop the 8-second poll so iOS doesn't queue ticks while the
        // process is suspended (which can spike memory on resume).
        if (ref.exists(artisanJobsProvider)) {
          ref.read(artisanJobsProvider.notifier).pausePolling();
        }
        // Drop the socket — it's redundant with FCM while backgrounded
        // and holds a TCP connection + event buffers that count against
        // the iOS jetsam budget.
        ref.read(socketServiceProvider).disconnect();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
