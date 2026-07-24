import 'package:api_client/mobile_diagnostics.dart' show debugLog;
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

    if (state is AuthOtpSent) {
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
      onResend: () async {
        try {
          await ref.read(authControllerProvider.notifier).resendOtp();
        } catch (_) {}
      },
      onResendWhatsApp: whatsappAvailable
          ? () async {
              await ref
                  .read(authControllerProvider.notifier)
                  .resendOtp(channel: 'whatsapp');
            }
          : null,
      onBack: () => ref.read(authControllerProvider.notifier).reset(),
    );
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

    if (freshDriverSignup) {
      driverDraftNotifier?.update(DriverRegistrationDraft());
    } else if (artisanDraft != null) {
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
          debugLog(() => '[Auth] post-signup artisan sync failed: $error');
          return;
        }
      }
      artisanDraftNotifier?.update(ArtisanRegistrationDraft());
    }
  }
}
