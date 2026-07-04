import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../../registration/providers/registration_controller.dart';
import '../providers/auth_controller.dart';

/// Phone number input.
///
/// Used by both sign-in (`mode = signIn`) and the final step of sign-up
/// (`mode = signUp`). In sign-up mode, the registration draft data is sent
/// along with the phone via POST /auth/register.
enum PhoneInputMode { signIn, signUp }

class ProviderPhoneInputScreen extends ConsumerStatefulWidget {
  const ProviderPhoneInputScreen({
    super.key,
    required this.mode,
    this.signUpRole,
  });

  final PhoneInputMode mode;
  final ProviderType? signUpRole;

  @override
  ConsumerState<ProviderPhoneInputScreen> createState() =>
      _ProviderPhoneInputScreenState();
}

class _ProviderPhoneInputScreenState
    extends ConsumerState<ProviderPhoneInputScreen> {
  bool _blockedDialogVisible = false;

  PhoneInputMode get mode => widget.mode;
  ProviderType? get signUpRole => widget.signUpRole;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next is AuthBlockedByOtherDevice && !_blockedDialogVisible) {
        _blockedDialogVisible = true;
        _showBlockedDialog(context, next.phone);
      } else if (next is! AuthBlockedByOtherDevice && _blockedDialogVisible) {
        _blockedDialogVisible = false;
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    });

    String? remoteError;
    bool isLoading = false;

    if (state is AuthUnauthenticated) {
      remoteError = state.error;
      isLoading = state.isLoading;
    }

    final title =
        mode == PhoneInputMode.signIn ? 'Welcome back' : 'Verify your phone';
    final subtitle = mode == PhoneInputMode.signIn
        ? 'Sign in with your registered phone number.'
        : "We'll send a code to confirm your number and finish your account.";

    return MyShopPhoneInputScreen(
      title: title,
      subtitle: subtitle,
      buttonLabel: 'Send code',
      isLoading: isLoading,
      errorText: remoteError,
      onErrorCleared: () =>
          ref.read(authControllerProvider.notifier).clearError(),
      onSubmit: (phone) => _submit(phone),
      bottomAction: mode == PhoneInputMode.signIn
          ? TextButton(
              onPressed: isLoading ? null : () => context.go('/signup/role'),
              style: TextButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: MyShopColors.primaryGoldDark,
              ),
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: "Don't have an account? ",
                      style: MyShopTypography.body1.copyWith(
                        color: MyShopColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: 'Sign up',
                      style: MyShopTypography.body1.copyWith(
                        color: MyShopColors.primaryGoldDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _submit(String phone) async {
    final notifier = ref.read(authControllerProvider.notifier);

    if (mode == PhoneInputMode.signIn) {
      await notifier.checkPhoneAndLogin(phone: phone);
    } else {
      final role = signUpRole ?? ProviderType.driver;

      if (role == ProviderType.driver) {
        final draft = ref.read(driverRegistrationProvider);
        await notifier.registerAndSendOtp(
          phone: phone,
          fullName: draft.fullName,
          type: 'driver',
          privacyPolicyAccepted: true,
          role: role,
          email: draft.email.isNotEmpty ? draft.email : null,
          rideCategories:
              draft.rideCategories.isNotEmpty ? draft.rideCategories : null,
          regionId: draft.regionId.isNotEmpty ? draft.regionId : null,
          referralCode: draft.referralCode.trim().isNotEmpty
              ? draft.referralCode.trim()
              : null,
          vehicleMake: draft.vehicleMake.trim().isNotEmpty
              ? draft.vehicleMake.trim()
              : null,
          vehicleModel: draft.vehicleModel.trim().isNotEmpty
              ? draft.vehicleModel.trim()
              : null,
          vehicleYear: int.tryParse(draft.vehicleYear.trim()),
          vehiclePlate: draft.vehiclePlate.trim().isNotEmpty
              ? draft.vehiclePlate.trim()
              : null,
          vehicleColor: draft.vehicleColor.trim().isNotEmpty
              ? draft.vehicleColor.trim()
              : null,
        );
      } else {
        final draft = ref.read(artisanRegistrationProvider);
        await notifier.registerAndSendOtp(
          phone: phone,
          fullName: draft.fullName,
          type: 'artisan',
          privacyPolicyAccepted: true,
          role: role,
          businessName:
              draft.businessName.isNotEmpty ? draft.businessName : null,
          email: draft.email.isNotEmpty ? draft.email : null,
          categories: draft.serviceCategories.isNotEmpty
              ? draft.serviceCategories
              : null,
          regionId: draft.regionId.isNotEmpty ? draft.regionId : null,
          referralCode: draft.referralCode.trim().isNotEmpty
              ? draft.referralCode.trim()
              : null,
        );
      }
    }
  }

  Future<void> _showBlockedDialog(BuildContext context, String phone) async {
    final controller = ref.read(authControllerProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(authControllerProvider);
            final blocked = state is AuthBlockedByOtherDevice ? state : null;
            final recoveryStatus =
                blocked?.recoveryRequestStatus ?? RecoveryRequestStatus.idle;
            final sendingRecovery =
                recoveryStatus == RecoveryRequestStatus.sending;
            final takingOver = blocked?.isTakingOver ?? false;
            final takeoverError = blocked?.takeoverError;
            final anyInFlight = sendingRecovery || takingOver;
            return AlertDialog(
              title: const Text('Already signed in elsewhere'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This account ($phone) is signed in on another device. '
                    'Choose "Sign me in here" to take over the session — '
                    "we'll send an OTP to confirm it's you and sign out the "
                    'other device. '
                    "If you don't recognise the other device, tap "
                    'Contact support instead.',
                  ),
                  if (takeoverError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      takeoverError,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      anyInFlight ? null : () => controller.forceTakeover(),
                  child: takingOver
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign me in here'),
                ),
                TextButton(
                  onPressed: anyInFlight
                      ? null
                      : () async {
                          await controller.requestSessionRecovery();
                          if (!dialogContext.mounted) return;
                          final after = ref.read(authControllerProvider);
                          if (after is AuthBlockedByOtherDevice) {
                            if (after.recoveryRequestStatus ==
                                RecoveryRequestStatus.sent) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Support has been notified. '
                                    "We'll get back to you shortly.",
                                  ),
                                ),
                              );
                            } else if (after.recoveryRequestStatus ==
                                RecoveryRequestStatus.failed) {
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Couldn't reach support. "
                                    'Please check your connection and try again.',
                                  ),
                                ),
                              );
                            }
                          }
                        },
                  child: sendingRecovery
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Contact support'),
                ),
                TextButton(
                  onPressed: anyInFlight
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop();
                          controller.dismissBlockedLogin();
                        },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
    _blockedDialogVisible = false;
  }
}
