import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/providers/availability_controller.dart';
import 'package:myshop_provider/src/core/providers/provider_status_provider.dart';
import 'package:myshop_provider/src/core/services/fcm_service.dart';
import 'package:api_client/api_client.dart';

void main() {
  test('Go Online fails closed before background-location disclosure',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final error = await container.read(availabilityControllerProvider).goOnline(
          backgroundLocationDisclosureAccepted: false,
        );

    expect(
      error,
      'Review and accept the background location disclosure to go online.',
    );
    expect(container.read(providerStatusProvider).isOffline, isTrue);
  });

  test(
      'Go Online fails before GPS when notification reachability is unavailable',
      () async {
    final container = ProviderContainer(
      overrides: [
        onlineNotificationReachabilityCheckProvider.overrideWithValue(
          () async =>
              'Enable notifications in Settings before going online so you can receive requests.',
        ),
      ],
    );
    addTearDown(container.dispose);

    final error = await container.read(availabilityControllerProvider).goOnline(
          backgroundLocationDisclosureAccepted: true,
        );

    expect(
      error,
      'Enable notifications in Settings before going online so you can receive requests.',
    );
    expect(container.read(providerStatusProvider).isOffline, isTrue);
  });

  test('maps eligibility reasons to approved actionable copy', () {
    const expiredLicence = ApiException(
      message: 'raw backend message',
      errorCode: 'PROVIDER_NOT_ELIGIBLE',
      details: {
        'reasonCodes': ['DOCUMENT_EXPIRED_DRIVERS_LICENCE'],
      },
    );
    const rmApproval = ApiException(
      message: 'raw backend message',
      errorCode: 'PROVIDER_NOT_ELIGIBLE',
      details: {
        'reasonCodes': ['RM_FINAL_APPROVAL_REQUIRED'],
      },
    );

    expect(
      friendlyAvailabilityApiError(expiredLicence),
      "Your driver's licence has expired. Upload the renewed document for "
      'approval before going online.',
    );
    expect(
      friendlyAvailabilityApiError(rmApproval),
      'Regional Manager approval is required before you can go online. '
      'Check Documents & Verification for the current status.',
    );
  });

  test('unknown eligibility reasons never expose backend prose', () {
    const error = ApiException(
      message: 'database table secret_internal failed',
      errorCode: 'PROVIDER_NOT_ELIGIBLE',
      details: {
        'reasonCodes': ['FUTURE_REASON'],
      },
    );

    final copy = friendlyAvailabilityApiError(error);
    expect(copy, isNot(contains('secret_internal')));
    expect(copy, contains('Review Documents & Verification'));
  });

  test('relaunch restore uses the no-prompt notification gate', () async {
    var manualGateCalls = 0;
    var restoreGateCalls = 0;
    final container = ProviderContainer(
      overrides: [
        onlineNotificationReachabilityCheckProvider.overrideWithValue(
          () async {
            manualGateCalls += 1;
            return 'Unexpected manual gate.';
          },
        ),
        onlineNotificationRestoreReachabilityCheckProvider.overrideWithValue(
          () async {
            restoreGateCalls += 1;
            return 'Enable notifications in Settings before restoring Online.';
          },
        ),
      ],
    );
    addTearDown(container.dispose);

    final error = await container
        .read(availabilityControllerProvider)
        .restorePriorOnlineIntent();

    expect(error, 'Enable notifications in Settings before restoring Online.');
    expect(restoreGateCalls, 1);
    expect(manualGateCalls, 0);
    expect(container.read(providerStatusProvider).isOffline, isTrue);
  });
}
