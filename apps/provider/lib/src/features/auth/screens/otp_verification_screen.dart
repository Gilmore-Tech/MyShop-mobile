import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../../registration/providers/registration_controller.dart';
import '../providers/auth_controller.dart';

/// 6-digit OTP verification screen.
///
/// Used for both sign-in and sign-up flows. The auth state determines context.
/// On successful verify, the controller fetches the user profile and
/// transitions directly to [AuthAuthenticated].
class ProviderOtpVerificationScreen extends ConsumerWidget {
  const ProviderOtpVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authControllerProvider);

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
      onBack: () => ref.read(authControllerProvider.notifier).reset(),
    );
  }

  /// Verify the OTP, then push any role-specific draft fields that
  /// `POST /auth/register` couldn't carry (vehicle details for driver,
  /// service radius for artisan) via the role's profile-update endpoint.
  /// Without this, the driver row lands with null vehicle columns and the
  /// account screen shows "Vehicle information: Not set up yet" forever.
  Future<void> _verifyAndFlushDraft(WidgetRef ref, String code) async {
    final controller = ref.read(authControllerProvider.notifier);

    final before = ref.read(authControllerProvider);
    final freshDriverSignup = before is AuthOtpSent &&
        before.isNewUser &&
        before.role == ProviderType.driver;
    final freshArtisanSignup = before is AuthOtpSent &&
        before.isNewUser &&
        before.role == ProviderType.artisan;

    await controller.verifyOtp(code);

    if (ref.read(authControllerProvider) is! AuthAuthenticated) return;

    if (freshDriverSignup) {
      final draft = ref.read(driverRegistrationProvider);
      final hasVehicle = draft.vehicleMake.isNotEmpty ||
          draft.vehicleModel.isNotEmpty ||
          draft.vehicleYear.isNotEmpty ||
          draft.vehiclePlate.isNotEmpty ||
          draft.vehicleColor.isNotEmpty;
      if (hasVehicle) {
        await controller.updateDriverProfile(
          UpdateDriverProfileRequest(
            vehicleMake:
                draft.vehicleMake.isNotEmpty ? draft.vehicleMake : null,
            vehicleModel:
                draft.vehicleModel.isNotEmpty ? draft.vehicleModel : null,
            vehicleYear:
                draft.vehicleYear.isNotEmpty ? draft.vehicleYear : null,
            vehiclePlate:
                draft.vehiclePlate.isNotEmpty ? draft.vehiclePlate : null,
            vehicleColor:
                draft.vehicleColor.isNotEmpty ? draft.vehicleColor : null,
          ),
        );
      }
      ref
          .read(driverRegistrationProvider.notifier)
          .update(DriverRegistrationDraft());
    } else if (freshArtisanSignup) {
      final draft = ref.read(artisanRegistrationProvider);
      // serviceRadiusKm is the only post-register artisan-only field on the
      // draft today. Only push when the user actually changed it from the
      // 5 km default so we don't overwrite a server-side default with one.
      if (draft.serviceRadiusKm != 5) {
        await controller.updateArtisanProfile(
          UpdateArtisanProfileRequest(
            serviceRadiusKm: draft.serviceRadiusKm,
          ),
        );
      }
      ref
          .read(artisanRegistrationProvider.notifier)
          .update(ArtisanRegistrationDraft());
    }
  }
}
