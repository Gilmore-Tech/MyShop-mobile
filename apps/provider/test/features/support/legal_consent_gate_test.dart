import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/service_notice_provider.dart';
import 'package:myshop_provider/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_provider/src/features/support/providers/support_providers.dart';
import 'package:myshop_provider/src/features/support/screens/legal_consent_route_screen.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

const _driverStatus = LegalConsentStatus(
  role: 'driver',
  current: false,
  requiresConsent: true,
  hasActiveWork: false,
  missingSlugs: ['terms'],
  documents: [],
);

const _acceptedStatus = LegalConsentStatus(
  role: 'driver',
  current: true,
  requiresConsent: false,
  hasActiveWork: false,
  missingSlugs: [],
  documents: [],
);

AuthAuthenticated _driverAuth(
  String roleAccountId, {
  String? topLevelId,
}) {
  return AuthAuthenticated(
    AuthUser(
      id: topLevelId ?? roleAccountId,
      phone: '+233200000000',
      fullName: 'Driver',
      role: AuthRole.driver,
      driverProfile: DriverProfile(
        id: roleAccountId,
        verificationStatus: 'approved',
        kycStatus: 'approved',
        policeCheckStatus: 'approved',
        onlineStatus: 'offline',
        serviceRadiusKm: 5,
        payoutPreference: 'standard',
        cancellationCount30d: 0,
        ghanaCardVerified: true,
        languagePref: 'en',
      ),
    ),
  );
}

AuthAuthenticated _artisanAuth(String roleAccountId) {
  return AuthAuthenticated(
    AuthUser(
      id: roleAccountId,
      phone: '+233200000000',
      fullName: 'Artisan',
      role: AuthRole.artisan,
      artisanProfile: ArtisanProfile(
        id: roleAccountId,
        verificationStatus: 'approved',
        kycStatus: 'approved',
        policeCheckStatus: 'approved',
        onlineStatus: 'offline',
        serviceRadiusKm: 5,
        shopCapacity: 'solo',
        maxConcurrentJobs: 1,
        payoutPreference: 'standard',
        completedJobsCount: 0,
        cancellationCount30d: 0,
        ghanaCardVerified: true,
        languagePref: 'en',
      ),
    ),
  );
}

RoleSessionIdentity _identity(
  String roleAccountId, {
  String subject = 'private-auth-id',
  String sessionId = 'sid-a',
  String role = 'driver',
}) {
  return RoleSessionIdentity(
    subject: subject,
    role: role,
    roleAccountId: roleAccountId,
    sessionId: sessionId,
  );
}

ScopedLegalConsentStatus _snapshot(
  String roleAccountId, {
  String subject = 'private-auth-id',
  String sessionId = 'sid-a',
  String role = 'driver',
  LegalConsentStatus status = _driverStatus,
}) {
  return ScopedLegalConsentStatus(
    identity: _identity(
      roleAccountId,
      subject: subject,
      sessionId: sessionId,
      role: role,
    ),
    status: status,
  );
}

void main() {
  test('exact role snapshot works without equating JWT subject to public ID',
      () {
    final status = usableProviderLegalConsentStatus(
      _driverAuth('driver-a'),
      AsyncData(_identity('driver-a', subject: 'private-auth-id')),
      AsyncData(_snapshot('driver-a', subject: 'private-auth-id')),
    );

    expect(status?.requiresConsent, isTrue);
  });

  test('offline, stale session and mismatched public IDs are neutral', () {
    final auth = _driverAuth('driver-a');

    expect(
      usableProviderLegalConsentStatus(
        auth,
        AsyncData(_identity('driver-a')),
        AsyncError(
          const NetworkException(message: 'offline'),
          StackTrace.empty,
        ),
      ),
      isNull,
    );
    expect(
      usableProviderLegalConsentStatus(
        auth,
        AsyncData(_identity('driver-a', sessionId: 'sid-b')),
        AsyncData(_snapshot('driver-a')),
      ),
      isNull,
    );
    expect(
      usableProviderLegalConsentStatus(
        _driverAuth('driver-a', topLevelId: 'driver-b'),
        AsyncData(_identity('driver-a')),
        AsyncData(_snapshot('driver-a')),
      ),
      isNull,
    );
  });

  test('driver consent cannot gate the sibling artisan role', () {
    expect(
      usableProviderLegalConsentStatus(
        _artisanAuth('artisan-a'),
        AsyncData(_identity('artisan-a', role: 'artisan')),
        AsyncData(_snapshot('driver-a')),
      ),
      isNull,
    );
  });

  test('service notice advances revalidation only after recovery', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(serviceNoticeProvider.notifier)
        .report(MobileServiceIssue.timeout);
    expect(
      container.read(serviceNoticeProvider).issue,
      MobileServiceIssue.timeout,
    );
    expect(container.read(serviceNoticeProvider).recoveryEpoch, 0);

    container.read(serviceNoticeProvider.notifier).recovered();
    expect(container.read(serviceNoticeProvider).issue, isNull);
    expect(container.read(serviceNoticeProvider).recoveryEpoch, 1);
  });

  test('submission issues use fixed copy and stay with the original session',
      () {
    final owner = _identity('driver-a');
    const malicious = 'SQLSTATE 42P01 private table and stack trace';

    expect(
      classifyLegalConsentSubmissionIssue(
        const NetworkException(
          message: malicious,
          kind: NetworkFailureKind.offline,
        ),
      ),
      MyShopLegalSubmissionIssue.offline,
    );
    expect(
      classifyLegalConsentSubmissionIssue(
        const ValidationException(message: malicious),
      ),
      MyShopLegalSubmissionIssue.invalidSelection,
    );
    expect(
      classifyLegalConsentSubmissionIssue(
        const ServerException(message: malicious, statusCode: 500),
      ),
      MyShopLegalSubmissionIssue.unavailable,
    );
    expect(
      legalConsentSubmissionIssueForSession(
        owner: owner,
        currentIdentity: _identity('driver-a', sessionId: 'sid-b'),
        error: const NetworkException(message: malicious),
      ),
      isNull,
    );
  });

  test('confirmation and retained documents remain exact-session owned', () {
    final owner = _identity('driver-a');
    final retained = _snapshot('driver-a');
    final accepted = _snapshot('driver-a', status: _acceptedStatus);

    expect(
      legalConsentConfirmationIssueForSession(
        owner: owner,
        currentIdentity: owner,
        refreshed: retained,
      ),
      MyShopLegalSubmissionIssue.confirmationPending,
    );
    expect(
      legalConsentConfirmationIssueForSession(
        owner: owner,
        currentIdentity: owner,
        refreshed: accepted,
      ),
      isNull,
    );
    expect(
      visibleLegalConsentStatusForSession(
        currentIdentity: owner,
        live: null,
        retained: retained,
      ),
      same(retained),
    );
    expect(
      visibleLegalConsentStatusForSession(
        currentIdentity: _identity('driver-a', sessionId: 'sid-b'),
        live: null,
        retained: retained,
      ),
      isNull,
    );
  });
}
