import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../../registration/providers/regions_provider.dart';
import '../../registration/providers/registration_controller.dart';
import '../providers/auth_controller.dart';
import '../widgets/blocked_device_dialog.dart';

/// 6-digit OTP verification screen.
///
/// Used for both sign-in and sign-up flows. The auth state determines context.
/// On successful verify, the controller fetches the user profile and
/// transitions directly to [AuthAuthenticated]. In the post-OTP provider login
/// a single-device conflict can surface here (the role is resolved after the
/// code is verified), so this screen also hosts the takeover dialog.
class ProviderOtpVerificationScreen extends ConsumerStatefulWidget {
  const ProviderOtpVerificationScreen({super.key});

  @override
  ConsumerState<ProviderOtpVerificationScreen> createState() =>
      _ProviderOtpVerificationScreenState();
}

class _ProviderOtpVerificationScreenState
    extends ConsumerState<ProviderOtpVerificationScreen> {
  bool _blockedDialogVisible = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final whatsappAvailable = ref.watch(otpChannelsProvider).maybeWhen(
          data: (channels) => channels.contains('whatsapp'),
          orElse: () => false,
        );

    if (state is AuthBlockedByOtherDevice && !_blockedDialogVisible) {
      _blockedDialogVisible = true;
      final phone = state.phone;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ref.read(authControllerProvider) is! AuthBlockedByOtherDevice) {
          _blockedDialogVisible = false;
          return;
        }
        showBlockedByOtherDeviceDialog(context, ref, phone).whenComplete(() {
          _blockedDialogVisible = false;
        });
      });
    }

    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      // Stale-cache edge case: the backend rejected the home region at
      // verify-otp. Drop the cached region list so the region step re-fetches
      // GET /v1/regions when the user backs out to re-select.
      if (next is AuthOtpSent && next.regionRejected) {
        ref.invalidate(regionsProvider);
      }
    });

    String phone = '';
    String? error;
    bool isVerifying = false;
    AuthOtpSent? otpState;

    if (state is AuthOtpSent) {
      otpState = state;
      phone = state.phone;
      error = state.error;
      isVerifying = state.isVerifying;
    } else if (state is AuthAuthenticated) {
      isVerifying = true;
    }

    return MyShopOtpVerificationScreen(
      phone: phone,
      isVerifying: isVerifying,
      errorText: error,
      onErrorCleared: () =>
          ref.read(authControllerProvider.notifier).clearError(),
      onVerify: (code) => _verifyAndFlushDraft(ref, code),
      onResendAttempt: () =>
          ref.read(authControllerProvider.notifier).resendOtp(),
      onResendWhatsAppAttempt: whatsappAvailable
          ? () => ref
              .read(authControllerProvider.notifier)
              .resendOtp(channel: 'whatsapp')
          : null,
      bottomAction: _canRemoveReferral(otpState)
          ? TextButton.icon(
              onPressed: () => _removeReferralAndRestart(otpState!),
              icon: const Icon(Icons.link_off_rounded),
              label: const Text('Remove code and request a new OTP'),
            )
          : null,
      onBack: () => ref.read(authControllerProvider.notifier).reset(),
    );
  }

  bool _canRemoveReferral(AuthOtpSent? state) {
    if (state == null ||
        !state.isNewUser ||
        !AuthErrorMapper.isReferralRegistrationErrorCode(state.errorCode)) {
      return false;
    }
    final role = state.role;
    if (role == ProviderType.driver) {
      return ref
          .read(driverRegistrationProvider)
          .referralCode
          .trim()
          .isNotEmpty;
    }
    if (role == ProviderType.artisan) {
      return ref
          .read(artisanRegistrationProvider)
          .referralCode
          .trim()
          .isNotEmpty;
    }
    return false;
  }

  void _removeReferralAndRestart(AuthOtpSent state) {
    final role = state.role;
    if (role == ProviderType.driver) {
      final draft = ref.read(driverRegistrationProvider);
      ref
          .read(driverRegistrationProvider.notifier)
          .update(draft.copyWith(referralCode: ''));
    } else if (role == ProviderType.artisan) {
      final draft = ref.read(artisanRegistrationProvider);
      ref
          .read(artisanRegistrationProvider.notifier)
          .update(draft.copyWith(referralCode: ''));
    } else {
      return;
    }
    ref.read(authControllerProvider.notifier).reset();
  }

  /// Verify the OTP, clear the driver draft created by the now-complete
  /// registration transaction, then push the one artisan-only draft field
  /// that `POST /auth/register` does not currently carry.
  ///
  /// Driver vehicle details and category slugs are part of registration. The
  /// backend atomically creates the explicit pending vehicle and its pending
  /// per-vehicle category rows. Re-sending legacy flattened vehicle fields to
  /// the profile endpoint is both redundant and forbidden after registration.
  Future<void> _verifyAndFlushDraft(WidgetRef ref, String code) async {
    final controller = ref.read(authControllerProvider.notifier);

    final before = ref.read(authControllerProvider);
    final freshDriverSignup = before is AuthOtpSent &&
        before.isNewUser &&
        before.role == ProviderType.driver;
    final freshArtisanSignup = before is AuthOtpSent &&
        before.isNewUser &&
        before.role == ProviderType.artisan;
    final artisanDraft =
        freshArtisanSignup ? ref.read(artisanRegistrationProvider) : null;
    final driverDraftNotifier = freshDriverSignup
        ? ref.read(driverRegistrationProvider.notifier)
        : null;
    final artisanDraftNotifier = freshArtisanSignup
        ? ref.read(artisanRegistrationProvider.notifier)
        : null;

    await controller.verifyOtp(code);

    // AuthController reports verification failures by restoring AuthOtpSent;
    // it does not throw. Never discard a registration draft unless the
    // complete authenticated profile has actually been published.
    if (ref.read(authControllerProvider) is! AuthAuthenticated) return;

    if (freshDriverSignup) {
      driverDraftNotifier?.update(DriverRegistrationDraft());
    } else if (artisanDraft != null) {
      // The production AuthController finalizes this draft as part of the
      // authenticated-session transition, including after a deferred profile
      // restore. Keep this local fallback for injected/test controllers, but
      // never send the radius update twice when the controller already did it.
      if (ref.read(artisanRegistrationProvider).fullName.isEmpty) return;
      // serviceRadiusKm is the only post-register artisan-only field on the
      // draft today. Only push when the user actually changed it from the
      // 5 km default so we don't overwrite a server-side default with one.
      if (artisanDraft.serviceRadiusKm != 5) {
        final error = await controller.updateArtisanProfile(
          UpdateArtisanProfileRequest(
            serviceRadiusKm: artisanDraft.serviceRadiusKm,
          ),
        );
        if (error != null) {
          debugPrint('[Auth] post-signup artisan sync failed: $error');
          return;
        }
      }
      artisanDraftNotifier?.update(ArtisanRegistrationDraft());
    }
  }
}
