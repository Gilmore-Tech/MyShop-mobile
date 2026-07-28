import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/providers/service_notice_provider.dart';
import 'package:myshop_client/src/features/auth/providers/auth_controller.dart';
import 'package:myshop_client/src/features/support/providers/support_providers.dart';
import 'package:myshop_client/src/features/support/screens/legal_consent_route_screen.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

const _status = LegalConsentStatus(
  role: 'client',
  current: false,
  requiresConsent: true,
  hasActiveWork: false,
  missingSlugs: ['terms'],
  documents: [],
);

const _acceptedStatus = LegalConsentStatus(
  role: 'client',
  current: true,
  requiresConsent: false,
  hasActiveWork: false,
  missingSlugs: [],
  documents: [],
);

AuthAuthenticated _clientAuth(
  String roleAccountId, {
  String? topLevelId,
}) {
  return AuthAuthenticated(
    UserProfile(
      id: topLevelId ?? roleAccountId,
      phone: '+233200000000',
      fullName: 'Client',
      languagePref: 'en',
      status: 'active',
      createdAt: '2026-01-01T00:00:00Z',
      updatedAt: '2026-01-01T00:00:00Z',
      client: ClientProfile(
        id: roleAccountId,
        languagePref: 'en',
        ghanaCardVerified: false,
        kycStatus: 'not_started',
      ),
    ),
  );
}

RoleSessionIdentity _identity(
  String roleAccountId, {
  String subject = 'private-auth-id',
  String sessionId = 'sid-a',
}) {
  return RoleSessionIdentity(
    subject: subject,
    role: 'client',
    roleAccountId: roleAccountId,
    sessionId: sessionId,
  );
}

ScopedLegalConsentStatus _snapshot(
  String roleAccountId, {
  String subject = 'private-auth-id',
  String sessionId = 'sid-a',
  LegalConsentStatus status = _status,
}) {
  return ScopedLegalConsentStatus(
    identity: _identity(
      roleAccountId,
      subject: subject,
      sessionId: sessionId,
    ),
    status: status,
  );
}

void main() {
  test('exact role snapshot works without equating JWT subject to public ID',
      () {
    final status = usableClientLegalConsentStatus(
      _clientAuth('client-a'),
      AsyncData(_identity('client-a', subject: 'private-auth-id')),
      AsyncData(_snapshot('client-a', subject: 'private-auth-id')),
    );

    expect(status?.requiresConsent, isTrue);
  });

  test('offline, loading, stale sessions and mismatched public IDs are neutral',
      () {
    final auth = _clientAuth('client-a');

    expect(
      usableClientLegalConsentStatus(
        auth,
        AsyncData(_identity('client-a')),
        AsyncError(
          const NetworkException(message: 'offline'),
          StackTrace.empty,
        ),
      ),
      isNull,
    );
    expect(
      usableClientLegalConsentStatus(
        auth,
        AsyncData(_identity('client-a')),
        const AsyncLoading(),
      ),
      isNull,
    );
    expect(
      usableClientLegalConsentStatus(
        auth,
        AsyncData(_identity('client-a', sessionId: 'sid-b')),
        AsyncData(_snapshot('client-a')),
      ),
      isNull,
    );
    expect(
      usableClientLegalConsentStatus(
        _clientAuth('client-a', topLevelId: 'client-b'),
        AsyncData(_identity('client-a')),
        AsyncData(_snapshot('client-a')),
      ),
      isNull,
    );
  });

  test('service notice advances revalidation only after recovery', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(serviceNoticeProvider.notifier)
        .report(MobileServiceIssue.offline);
    expect(
      container.read(serviceNoticeProvider).issue,
      MobileServiceIssue.offline,
    );
    expect(container.read(serviceNoticeProvider).recoveryEpoch, 0);

    container.read(serviceNoticeProvider.notifier).recovered();
    expect(container.read(serviceNoticeProvider).issue, isNull);
    expect(container.read(serviceNoticeProvider).recoveryEpoch, 1);
  });

  test('submission issues use fixed copy and stay with the original session',
      () {
    final owner = _identity('client-a');
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
        currentIdentity: _identity('client-a', sessionId: 'sid-b'),
        error: const NetworkException(message: malicious),
      ),
      isNull,
    );
  });

  test('confirmation and retained documents remain exact-session owned', () {
    final owner = _identity('client-a');
    final retained = _snapshot('client-a');
    final accepted = _snapshot('client-a', status: _acceptedStatus);

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
        currentIdentity: _identity('client-a', sessionId: 'sid-b'),
        live: null,
        retained: retained,
      ),
      isNull,
    );
  });
}
