import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:myshop_client/src/app/client_app.dart';
import 'package:myshop_client/src/app/router.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/service_notice_provider.dart';
import 'package:myshop_client/src/features/auth/data/auth_repository.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/ride/providers/ride_provider.dart'
    show activeRideIdProvider;
import 'package:myshop_client/src/features/support/providers/support_providers.dart';
import 'package:shared_models/shared_models.dart';

class _MockTokenStorage extends Mock implements TokenStorage {}

class _MockTelemetry extends Mock implements SystemTelemetryService {}

class _AuthenticatedController extends ClientAuthController {
  _AuthenticatedController(ClientAuthState initial)
      : super(
          ClientAuthRepository(
            service: MockAuthService(),
            tokenStorage: _MockTokenStorage(),
            deviceIdProvider: DeviceIdProvider(_MockTokenStorage()),
          ),
        ) {
    state = initial;
  }

  @override
  Future<void> bootstrap() async {}
}

const _identity = RoleSessionIdentity(
  subject: 'private-auth-id',
  role: 'client',
  roleAccountId: 'client-a',
  sessionId: 'session-a',
);

AuthAuthenticated _authenticatedClient() {
  return AuthAuthenticated(
    const UserProfile(
      id: 'client-a',
      phone: '+233200000000',
      fullName: 'Client',
      languagePref: 'en',
      status: 'active',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      client: ClientProfile(
        id: 'client-a',
        languagePref: 'en',
        ghanaCardVerified: false,
        kycStatus: 'not_started',
      ),
    ),
  );
}

ProviderContainer _routerContainer({bool Function()? requiresConsent}) {
  final controller = _AuthenticatedController(_authenticatedClient());
  return ProviderContainer(
    overrides: [
      clientAuthControllerProvider.overrideWith((_) => controller),
      hasSeenOnboardingProvider.overrideWith((_) => true),
      onboardingFlagLoadedProvider.overrideWith((_) => true),
      pendingReplayOnboardingProvider.overrideWith((_) => false),
      clientRoleSessionIdentityProvider.overrideWith((_) async => _identity),
      legalConsentStatusProvider.overrideWith(
        (_) async {
          final requiresReview = requiresConsent?.call() ?? false;
          return ScopedLegalConsentStatus(
            identity: _identity,
            status: LegalConsentStatus(
              role: 'client',
              current: !requiresReview,
              requiresConsent: requiresReview,
              hasActiveWork: false,
              missingSlugs: requiresReview ? const ['terms'] : const [],
              documents: const [],
            ),
          );
        },
      ),
      systemTelemetryProvider.overrideWithValue(_MockTelemetry()),
    ],
  );
}

void main() {
  test(
    'router provider does not watch redirect state and recreate GoRouter',
    () {
      final source = File('lib/src/app/router.dart').readAsStringSync();
      final providerStart = source.indexOf(
        'final routerProvider = Provider<GoRouter>',
      );
      final providerEnd = source.indexOf(
        'GoRouter _buildRouter',
        providerStart,
      );
      final providerBody = source.substring(providerStart, providerEnd);

      expect(providerStart, greaterThanOrEqualTo(0));
      expect(providerEnd, greaterThan(providerStart));
      expect(providerBody, isNot(contains('ref.watch(')));
      expect(providerBody, contains('_ClientRouterRefresh'));
      expect(source, contains('refreshListenable: refresh'));
      expect(source, contains('ref.read(clientAuthControllerProvider)'));
      expect(source, contains('ref.read(legalConsentStatusProvider)'));
    },
  );

  for (final path in const [AppRoutes.rideMatching, AppRoutes.rideTracking]) {
    test('legal revalidation preserves $path on the same router', () async {
      var requiresConsent = false;
      final container = _routerContainer(
        requiresConsent: () => requiresConsent,
      );
      addTearDown(container.dispose);
      final router = container.read(routerProvider);

      router.go(path);
      await Future<void>.delayed(Duration.zero);
      expect(router.routeInformationProvider.value.uri.path, path);

      requiresConsent = true;
      container.invalidate(legalConsentStatusProvider);
      await container.read(legalConsentStatusProvider.future);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(routerProvider), same(router));
      expect(router.routeInformationProvider.value.uri.path, path);
    });
  }

  testWidgets(
    'automatic readiness recovery dismisses notice without replacing route',
    (tester) async {
      var readinessProbes = 0;
      final testRouter = GoRouter(
        initialLocation: AppRoutes.rideMatching,
        routes: [
          GoRoute(
            path: AppRoutes.rideMatching,
            builder: (_, __) => const Scaffold(
              body: TextField(key: Key('preserved-active-route-field')),
            ),
          ),
        ],
      );
      addTearDown(testRouter.dispose);

      final base = _routerContainer();
      final container = ProviderContainer(
        parent: base,
        overrides: [
          routerProvider.overrideWithValue(testRouter),
          clientServiceReadinessProbeProvider.overrideWithValue(() async {
            readinessProbes++;
          }),
          clientServiceRecoveryDelayProvider.overrideWithValue(
            (_) => Duration.zero,
          ),
        ],
      );
      container
          .read(serviceNoticeProvider.notifier)
          .report(MobileServiceIssue.offline);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const ClientApp(),
        ),
      );
      await tester.enterText(
        find.byKey(const Key('preserved-active-route-field')),
        'active ride draft',
      );
      expect(find.text('No internet connection'), findsOneWidget);

      await tester.pump();
      await tester.pump();

      expect(readinessProbes, 1);
      expect(find.text('No internet connection'), findsNothing);
      expect(find.text('active ride draft'), findsOneWidget);
      expect(
        testRouter.routeInformationProvider.value.uri.path,
        AppRoutes.rideMatching,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      base.dispose();
      await tester.pump(const Duration(milliseconds: 1));
    },
  );

  for (final path in const [
    AppRoutes.rideMatching,
    AppRoutes.rideDriverFound,
    AppRoutes.rideTracking,
  ]) {
    testWidgets(
      '$path keeps a compact notice and usable action before ride id hydration',
      (tester) async {
        var actionTaps = 0;
        final testRouter = GoRouter(
          initialLocation: path,
          routes: [
            GoRoute(
              path: path,
              builder: (_, __) => Scaffold(
                body: Center(
                  child: FilledButton(
                    key: const Key('active-route-action'),
                    onPressed: () => actionTaps++,
                    child: const Text('Ride action'),
                  ),
                ),
              ),
            ),
          ],
        );
        addTearDown(testRouter.dispose);

        final base = _routerContainer();
        final container = ProviderContainer(
          parent: base,
          overrides: [
            routerProvider.overrideWithValue(testRouter),
            clientServiceReadinessProbeProvider.overrideWithValue(() async {}),
            clientServiceRecoveryDelayProvider.overrideWithValue(
              (_) => const Duration(hours: 1),
            ),
          ],
        );
        expect(container.read(activeRideIdProvider), isNull);
        container
            .read(serviceNoticeProvider.notifier)
            .report(MobileServiceIssue.offline);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const ClientApp(),
          ),
        );

        expect(
          find.byKey(const Key('service-connectivity-notice')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('service-connectivity-modal-barrier')),
          findsNothing,
        );
        await tester.tap(find.byKey(const Key('active-route-action')));
        await tester.pump();
        expect(actionTaps, 1);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        container.dispose();
        base.dispose();
        await tester.pump(const Duration(milliseconds: 1));
      },
    );
  }
}
