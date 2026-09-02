import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/support_contacts.dart';
import '../../profile/providers/provider_type_provider.dart';
import '../../registration/providers/categories_provider.dart';
import '../../registration/providers/regions_provider.dart';
import '../../registration/providers/registration_controller.dart';
import '../../registration/providers/ride_categories_provider.dart';
import '../providers/auth_controller.dart';
import '../widgets/blocked_device_dialog.dart';

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
  bool _legalRefreshHandled = false;
  String? _lastSubmittedPhone;

  PhoneInputMode get mode => widget.mode;
  ProviderType? get signUpRole => widget.signUpRole;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

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

    String? remoteError;
    bool isLoading = false;
    bool requiresRoleRecoverySupport = false;
    String? remoteErrorCode;
    Map<String, String> remoteFieldErrors = const {};

    if (state is AuthUnauthenticated) {
      remoteError = state.error;
      remoteErrorCode = state.errorCode;
      remoteFieldErrors = state.fieldErrors;
      isLoading = state.isLoading;
      requiresRoleRecoverySupport = state.requiresRoleRecoverySupport;
      if (state.requiresLegalRefresh && !_legalRefreshHandled) {
        _legalRefreshHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final role = signUpRole ?? ProviderType.driver;
          ref.read(termsAcceptedProvider(role).notifier).state = false;
          ref.read(privacyAcceptedProvider(role).notifier).state = false;
          ref.invalidate(registrationLegalDocumentsProvider(role));
          MyShopToast.show(
            context,
            message:
                'Terms or Privacy changed. Review the current versions again.',
          );
          context.go(role == ProviderType.driver
              ? '/signup/driver?step=4'
              : '/signup/artisan?step=3');
        });
      }
    }
    final role = signUpRole ?? ProviderType.driver;
    final correction = mode == PhoneInputMode.signUp
        ? registrationCorrectionForErrorCode(remoteErrorCode, role) ??
            registrationCorrectionForFieldErrors(remoteFieldErrors, role)
        : null;
    final canRemoveReferral = mode == PhoneInputMode.signUp &&
        AuthErrorMapper.isReferralRegistrationErrorCode(remoteErrorCode) &&
        _currentReferralCode(role).isNotEmpty;

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
      ghanaOnly: mode == PhoneInputMode.signUp,
      phoneValidator:
          mode == PhoneInputMode.signUp ? Validators.ghanaE164Phone : null,
      invalidPhoneMessage: mode == PhoneInputMode.signUp
          ? 'Enter a valid Ghana phone number.'
          : 'Enter a valid phone number.',
      bottomAction: requiresRoleRecoverySupport
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  onPressed: isLoading ? null : _startRoleRecovery,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    foregroundColor: MyShopColors.primaryGoldDark,
                  ),
                  icon: const Icon(Icons.restore),
                  label: const Text('Request account recovery'),
                ),
                TextButton.icon(
                  onPressed: isLoading ? null : _contactRecoverySupport,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 42),
                    foregroundColor: MyShopColors.textSecondary,
                  ),
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Contact support'),
                ),
              ],
            )
          : canRemoveReferral
              ? TextButton.icon(
                  key: const Key(
                    'provider-remove-referral-and-continue',
                  ),
                  onPressed: isLoading
                      ? null
                      : () => _removeReferralCodeAndContinue(role),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    foregroundColor: MyShopColors.primaryGoldDark,
                  ),
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Remove code and continue'),
                )
              : correction != null
                  ? TextButton.icon(
                      onPressed: isLoading
                          ? null
                          : () => _reviewBackendCorrection(
                                signUpRole ?? ProviderType.driver,
                                correction,
                                remoteErrorCode,
                              ),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        foregroundColor: MyShopColors.primaryGoldDark,
                      ),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(correction.message),
                    )
                  : mode == PhoneInputMode.signIn
                      ? TextButton(
                          onPressed: isLoading
                              ? null
                              : () => context.go('/signup/role'),
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
    _lastSubmittedPhone = phone;
    final notifier = ref.read(authControllerProvider.notifier);

    if (mode == PhoneInputMode.signIn) {
      await notifier.checkPhoneAndLogin(phone: phone);
    } else {
      final role = signUpRole ?? ProviderType.driver;
      final regions = ref.read(regionsProvider).valueOrNull;
      final regionSelectionRequired = regions != null && regions.length > 1;
      final draftIssue = role == ProviderType.driver
          ? firstDriverRegistrationIssue(
              ref.read(driverRegistrationProvider),
              regionSelectionRequired: regionSelectionRequired,
            )
          : firstArtisanRegistrationIssue(
              ref.read(artisanRegistrationProvider),
              regionSelectionRequired: regionSelectionRequired,
            );
      if (draftIssue != null) {
        _returnToRegistration(role, draftIssue);
        return;
      }

      RequiredLegalDocuments? legal;
      try {
        legal = await ref.read(registrationLegalDocumentsProvider(role).future);
      } catch (_) {
        // The legal request itself remains visible on the review step, where
        // it can be retried. Registration must fail closed here.
      }
      if (!mounted) return;
      if (legal == null ||
          legal.documents.length != 2 ||
          !ref.read(policyAcceptedProvider(role))) {
        _returnToRegistration(
          role,
          RegistrationDraftIssue(
            step: role == ProviderType.driver ? 4 : 3,
            message: 'Review and accept both current legal documents.',
          ),
        );
        return;
      }

      if (role == ProviderType.driver) {
        final draft = ref.read(driverRegistrationProvider);
        await notifier.registerAndSendOtp(
          phone: phone,
          fullName: draft.fullName,
          type: 'driver',
          legalAcceptances: legal.selections,
          role: role,
          email: draft.email.trim(),
          rideCategories:
              draft.rideCategories.isNotEmpty ? draft.rideCategories : null,
          regionId: draft.regionId.isNotEmpty ? draft.regionId : null,
          referralCode: draft.referralCode.trim().isNotEmpty
              ? draft.referralCode.trim().toUpperCase()
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
          legalAcceptances: legal.selections,
          role: role,
          businessName: draft.businessName.trim().isNotEmpty
              ? draft.businessName.trim()
              : null,
          email: draft.email.trim(),
          categories: draft.serviceCategories.isNotEmpty
              ? draft.serviceCategories
              : null,
          regionId: draft.regionId.isNotEmpty ? draft.regionId : null,
          referralCode: draft.referralCode.trim().isNotEmpty
              ? draft.referralCode.trim().toUpperCase()
              : null,
        );
      }
    }
  }

  void _returnToRegistration(
    ProviderType role,
    RegistrationDraftIssue issue, {
    bool showToast = true,
  }) {
    ref.read(showRegistrationErrorsProvider.notifier).state = true;
    if (showToast) {
      MyShopToast.show(context, message: issue.message);
    }
    final route =
        role == ProviderType.driver ? '/signup/driver' : '/signup/artisan';
    context.go('$route?step=${issue.step}');
  }

  void _reviewBackendCorrection(
    ProviderType role,
    RegistrationDraftIssue issue,
    String? errorCode,
  ) {
    if (errorCode == 'INVALID_CATEGORY') {
      final draft = ref.read(artisanRegistrationProvider);
      ref.read(artisanRegistrationProvider.notifier).update(
            draft.copyWith(serviceCategories: const []),
          );
      ref.invalidate(categoriesProvider);
    } else if (errorCode == 'INVALID_RIDE_CATEGORY') {
      final draft = ref.read(driverRegistrationProvider);
      ref.read(driverRegistrationProvider.notifier).update(
            draft.copyWith(rideCategories: const []),
          );
      ref.invalidate(rideCategoryOptionsProvider);
    } else if (errorCode == 'INVALID_REGION') {
      if (role == ProviderType.driver) {
        final draft = ref.read(driverRegistrationProvider);
        ref.read(driverRegistrationProvider.notifier).update(
              draft.copyWith(regionId: ''),
            );
      } else {
        final draft = ref.read(artisanRegistrationProvider);
        ref.read(artisanRegistrationProvider.notifier).update(
              draft.copyWith(regionId: ''),
            );
      }
      ref.invalidate(regionsProvider);
    }
    _returnToRegistration(role, issue, showToast: false);
  }

  String _currentReferralCode(ProviderType role) {
    return role == ProviderType.driver
        ? ref.read(driverRegistrationProvider).referralCode.trim()
        : ref.read(artisanRegistrationProvider).referralCode.trim();
  }

  Future<void> _removeReferralCodeAndContinue(ProviderType role) async {
    final phone = _lastSubmittedPhone;
    if (phone == null || _currentReferralCode(role).isEmpty) return;

    if (role == ProviderType.driver) {
      final draft = ref.read(driverRegistrationProvider);
      ref.read(driverRegistrationProvider.notifier).update(
            draft.copyWith(referralCode: ''),
          );
    } else {
      final draft = ref.read(artisanRegistrationProvider);
      ref.read(artisanRegistrationProvider.notifier).update(
            draft.copyWith(referralCode: ''),
          );
    }

    ref.read(authControllerProvider.notifier).clearError();
    await _submit(phone);
  }

  Future<void> _contactRecoverySupport() async {
    final opened = await SupportChannels.openEmail(
      to: providerSupportEmail,
      subject: 'Provider role recovery request',
    );
    if (!opened && mounted) {
      MyShopToast.show(
        context,
        message: 'Email $providerSupportEmail for recovery help.',
        duration: const Duration(seconds: 5),
      );
    }
  }

  Future<void> _startRoleRecovery() async {
    final phone = _lastSubmittedPhone;
    final role = signUpRole ?? ProviderType.driver;
    if (phone == null || phone.isEmpty) {
      MyShopToast.show(
        context,
        message: 'Enter the phone number that owned the deleted provider role.',
      );
      return;
    }
    final roleName = role == ProviderType.artisan ? 'artisan' : 'driver';
    final repository = ref.read(authRepositoryProvider);
    await showMyShopRoleAccountRecoveryDialog(
      context: context,
      phone: phone,
      role: roleName,
      requestKey: const Uuid().v4(),
      requestOtp: () =>
          repository.requestRoleAccountRecoveryOtp(phone, roleName),
      verifyOtp: (otp, requestKey) async {
        await repository.verifyRoleAccountRecoveryOtp(
          phone: phone,
          role: roleName,
          code: otp,
          requestKey: requestKey,
        );
      },
      errorMessage: (error) => error is ApiException
          ? AuthErrorMapper.message(error)
          : 'Recovery could not be requested. Please try again.',
    );
  }
}
