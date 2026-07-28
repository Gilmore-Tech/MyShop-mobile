import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import 'router.dart';
import 'theme_provider.dart';
import '../core/providers/app_update_provider.dart';
import '../core/providers/provider_location_notice_provider.dart';
import '../core/providers/service_notice_provider.dart';
import '../core/widgets/provider_location_notice_banner.dart';
import '../core/di/providers.dart' show dioProvider, systemTelemetryProvider;
import '../features/auth/providers/auth_controller.dart';
import '../features/ride/providers/ride_provider.dart'
    show activeRideIdProvider;
import '../features/services/providers/active_job_provider.dart'
    show trackedJobIdProvider;
import '../features/support/providers/support_providers.dart';

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
    ref.read(systemTelemetryProvider).trackLifecycle(state);
  }

  Future<void> _retryService() async {
    try {
      await probeMobileServiceReadiness(
        ref.read(dioProvider),
        onReady: () => ref.invalidate(legalConsentStatusProvider),
      );
    } catch (_) {
      // The interceptor keeps the notice visible with safe local copy.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeNotifierProvider);
    final updateRequirement = ref.watch(appUpdateRequirementProvider);
    final serviceIssue = ref.watch(serviceNoticeProvider).issue;
    final currentPath = router.routerDelegate.currentConfiguration.uri.path;
    final hasActiveWork = ref.watch(activeRideIdProvider) != null ||
        ref.watch(trackedJobIdProvider) != null ||
        currentPath == AppRoutes.rideTracking ||
        (currentPath.startsWith('/services/job/') &&
            (currentPath.endsWith('/active') ||
                currentPath.endsWith('/tracking')));
    final providerLocationNotice = ref.watch(providerLocationNoticeProvider);
    final auth = ref.watch(clientAuthControllerProvider);
    final legalConsent = auth is AuthAuthenticated
        ? ref.watch(legalConsentStatusProvider)
        : null;
    final legalStatusError =
        legalConsent?.hasError == true ? legalConsent?.error : null;
    final effectiveServiceIssue =
        mobileServiceIssueForLegalStatusError(legalStatusError) ?? serviceIssue;

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
        return MyShopServiceNoticeOverlay(
          kind: effectiveServiceIssue == null
              ? null
              : _noticeKind(effectiveServiceIssue),
          hasActiveWork: hasActiveWork,
          onRetry: _retryService,
          topNotices: [
            if (providerLocationNotice != null)
              ProviderLocationNoticeBanner(notice: providerLocationNotice),
          ],
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

MyShopServiceNoticeKind _noticeKind(MobileServiceIssue issue) {
  return switch (issue) {
    MobileServiceIssue.offline => MyShopServiceNoticeKind.offline,
    MobileServiceIssue.timeout => MyShopServiceNoticeKind.timeout,
    MobileServiceIssue.unavailable => MyShopServiceNoticeKind.unavailable,
  };
}
