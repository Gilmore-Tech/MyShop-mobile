import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../../driver_home/data/earnings_service.dart';
import '../../driver_home/providers/driver_earnings_provider.dart';

/// Drives the "Request Payout" tap flow for both the driver and artisan
/// dashboards.
///
/// Flow:
///   1. Pull the provider's stored `payoutMethod` from `currentUserProvider`.
///      If missing, surface a snackbar offering a deep-link to the payout
///      method screen and bail.
///   2. POST `/payments/payouts/request` with the stored method via
///      [EarningsService.requestPayout] (idempotency key auto-generated).
///   3. On success, invalidate `driverPayoutsProvider` so the new row
///      appears immediately and `driverEarningsProvider` so the available
///      balance updates. Show a "Payout requested" snackbar.
///   4. On failure, decode the backend's error code into the tailored copy
///      already baked into the [PayoutRequestResult] message.
///
/// Returns `true` on success, `false` otherwise — callers don't usually
/// need this, but it's handy for tests and could drive analytics later.
/// The caller is responsible for any per-button loading indicator (see
/// [requestProviderPayoutWith] for the typical ConsumerStatefulWidget
/// flow).
Future<bool> requestProviderPayout(
  BuildContext context,
  WidgetRef ref,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final user = ref.read(currentUserProvider);
  final method = user?.isDriver == true
      ? user?.driverProfile?.payoutMethod
      : user?.artisanProfile?.payoutMethod;

  if (method == null || method.isEmpty) {
    messenger.showSnackBar(
      SnackBar(
        content: const Text(
          'Add a payout method first to request payouts.',
        ),
        action: SnackBarAction(
          label: 'Add',
          textColor: MyShopColors.primaryGold,
          onPressed: () => context.push('/account/payouts'),
        ),
      ),
    );
    return false;
  }

  final result =
      await ref.read(earningsServiceProvider).requestPayout(method: method);

  if (!context.mounted) return result.success;

  if (result.success) {
    ref.invalidate(driverPayoutsProvider);
    ref.invalidate(driverEarningsProvider);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Payout requested — funds usually arrive in 5 minutes.'),
      ),
    );
    return true;
  }

  // Some failures are best surfaced with an action (e.g. NO_PAYOUT_METHOD
  // is unreachable here because we pre-checked, but the same UX applies if
  // the backend disagrees with the cached profile, e.g. METHOD_MISMATCH).
  final showAccountAction = result.code == 'PAYOUT_METHOD_MISMATCH' ||
      result.code == 'NO_PAYOUT_METHOD';
  messenger.showSnackBar(
    SnackBar(
      content: Text(result.message ?? 'Payout failed. Please try again.'),
      action: showAccountAction
          ? SnackBarAction(
              label: 'Update',
              textColor: MyShopColors.primaryGold,
              onPressed: () => context.push('/account/payouts'),
            )
          : null,
    ),
  );
  return false;
}
