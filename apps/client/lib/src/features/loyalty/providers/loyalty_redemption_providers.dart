import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/loyalty_repository.dart';
import '../domain/loyalty_models.dart';

/// Repository wrapping the loyalty endpoints + config rate.
final loyaltyRepositoryProvider = Provider<LoyaltyRepository>((ref) {
  return LoyaltyRepository(
    userService: ref.watch(userServiceProvider),
    loyaltyService: ref.watch(loyaltyServiceProvider),
    configService: ref.watch(platformConfigServiceProvider),
  );
});

/// Current loyalty balance, read from the in-memory auth profile. Updates
/// app-wide once [ClientAuthController.refreshProfile] re-fetches `/users/me`
/// after a redemption (or after the backend auto-refunds a cancelled booking).
final loyaltyBalanceProvider = Provider<int>((ref) {
  final authState = ref.watch(clientAuthControllerProvider);
  return authState is AuthAuthenticated
      ? (authState.profile.client?.loyaltyPointsBalance ?? 0)
      : 0;
});

/// Admin-tunable redemption economics. Kept alive (not autoDispose) so the
/// rate is fetched once and shared by every booking sheet in the session.
final loyaltyRateProvider = FutureProvider<LoyaltyRate>((ref) async {
  return ref.watch(loyaltyRepositoryProvider).fetchRate();
});

/// The redemption applied to a given booking, keyed by booking id. `null` until
/// the client redeems against it. Both the ride sheet and the job payment
/// screen watch this to show the discount line and disable the redeem control
/// (one redemption per booking — also enforced server-side).
///
/// Deliberately NOT autoDispose: the applied state must survive the redeem
/// sheet closing and the fare card rebuilding while the booking is open.
final appliedRedemptionProvider =
    StateProvider.family<LoyaltyRedemption?, String>((ref, bookingId) => null);
