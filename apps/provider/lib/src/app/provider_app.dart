import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../core/providers/app_lifecycle_provider.dart';
import '../core/providers/availability_controller.dart';
import '../core/providers/provider_status_provider.dart';
import '../core/providers/socket_provider.dart';
import '../core/services/fcm_service.dart';
import '../features/artisan_jobs/providers/artisan_jobs_provider.dart';
import '../features/auth/providers/auth_controller.dart';
import '../features/earnings/providers/earnings_providers.dart';
import '../features/earnings/providers/ratings_provider.dart';
import '../features/profile/providers/verification_provider.dart';
import '../features/trips/providers/driver_trips_provider.dart';
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
        // Flip the foreground flag first so any provider listening on
        // `appForegroundedProvider` (e.g. the open-jobs REST poller)
        // re-enables itself before the network calls below fire.
        ref.read(appForegroundedProvider.notifier).state = true;
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
        // Bust the earnings-flavoured caches. Catches every "socket
        // missed a `ride:state`/`job:state` completion while we were
        // backgrounded" scenario — SOS dialer handoff, incoming phone
        // call, screen lock past iOS's WS suspend threshold, app
        // switcher trip, mobile-data cell handoff. The backend has
        // already written the Payment row by the time we get here;
        // we just need the dashboard providers to refetch instead of
        // serving the pre-completion cache.
        try {
          ref.invalidate(todayCardProvider);
          ref.invalidate(earningsSummaryProvider);
          ref.invalidate(earningsReportProvider);
          ref.invalidate(activeTodayCardProvider);
          ref.invalidate(payoutsProvider);
          ref.invalidate(providerRatingsProvider);
          ref.invalidate(driverTripsProvider);
          // Catch admin document approvals/rejections that landed while the
          // app was backgrounded — verification status is otherwise cached
          // for the whole session.
          ref.invalidate(verificationStatusProvider);
        } catch (_) {
          // Providers may not be mounted on a cold-start resume —
          // harmless, the next subscription will fetch fresh anyway.
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        // Tell every foreground-only loop (REST pollers, retry timers)
        // to pause. Without this they keep firing GET /jobs every 10s
        // into a Doze-suspended network stack — DNS fails, log spam,
        // wasted battery.
        ref.read(appForegroundedProvider.notifier).state = false;
        // Stop the 8-second poll so iOS doesn't queue ticks while the
        // process is suspended (which can spike memory on resume).
        if (ref.exists(artisanJobsProvider)) {
          ref.read(artisanJobsProvider.notifier).pausePolling();
        }
        // Refresh the backend's liveness heartbeat one last time. The
        // socket bridge's 4s heartbeat is about to stop firing (Doze /
        // iOS suspend), and the backend's zombie-offline cron flips us
        // offline as soon as the Redis TTL expires — at which point the
        // matcher's SQL filter excludes us and inbound jobs fall through
        // to admin even though FCM could have woken the device. This
        // resets the TTL to a full 5-min window. Fire-and-forget.
        ref.read(availabilityControllerProvider).refreshHeartbeat();
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

    // Construct FirebaseMessaging only after asynchronous startup has
    // initialized Firebase; doing it on the first frame can throw.
    if (ref.watch(firebaseReadyProvider)) {
      ref.watch(fcmTapBridgeProvider);
    }

    return MaterialApp.router(
      title: 'MyShop Provider',
      debugShowCheckedModeBanner: false,
      theme: MyShopTheme.light,
      routerConfig: router,
    );
  }
}
