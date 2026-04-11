import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/providers/auth_controller.dart';
import '../../profile/providers/provider_type_provider.dart';

/// Tracks which role the user picked at signup; null until role picker.
final pendingRoleProvider = StateProvider<ProviderType?>((_) => null);

/// Driver registration draft.
class DriverRegistrationDraft {
  DriverRegistrationDraft({
    this.fullName = '',
    this.email = '',
    this.ghanaCardNumber = '',
    this.vehicleMake = '',
    this.vehicleModel = '',
    this.vehicleYear = '',
    this.vehiclePlate = '',
    this.vehicleColor = '',
    this.isSubmitting = false,
    this.error,
  });

  final String fullName;
  final String email;
  final String ghanaCardNumber;
  final String vehicleMake;
  final String vehicleModel;
  final String vehicleYear;
  final String vehiclePlate;
  final String vehicleColor;
  final bool isSubmitting;
  final String? error;

  DriverRegistrationDraft copyWith({
    String? fullName,
    String? email,
    String? ghanaCardNumber,
    String? vehicleMake,
    String? vehicleModel,
    String? vehicleYear,
    String? vehiclePlate,
    String? vehicleColor,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) =>
      DriverRegistrationDraft(
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        ghanaCardNumber: ghanaCardNumber ?? this.ghanaCardNumber,
        vehicleMake: vehicleMake ?? this.vehicleMake,
        vehicleModel: vehicleModel ?? this.vehicleModel,
        vehicleYear: vehicleYear ?? this.vehicleYear,
        vehiclePlate: vehiclePlate ?? this.vehiclePlate,
        vehicleColor: vehicleColor ?? this.vehicleColor,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
      );

  bool get isComplete =>
      fullName.isNotEmpty &&
      email.isNotEmpty &&
      ghanaCardNumber.isNotEmpty &&
      vehicleMake.isNotEmpty &&
      vehicleModel.isNotEmpty &&
      vehicleYear.isNotEmpty &&
      vehiclePlate.isNotEmpty &&
      vehicleColor.isNotEmpty;
}

class DriverRegistrationController
    extends StateNotifier<DriverRegistrationDraft> {
  DriverRegistrationController(this._repo, this._auth)
      : super(DriverRegistrationDraft());

  final AuthRepository _repo;
  final AuthController _auth;

  void update(DriverRegistrationDraft draft) => state = draft;

  Future<bool> submit(String phone) async {
    if (!state.isComplete) {
      state = state.copyWith(error: 'Please fill in all fields.');
      return false;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final user = await _repo.registerDriver(
        phone: phone,
        payload: DriverRegistrationPayload(
          fullName: state.fullName,
          email: state.email,
          ghanaCardNumber: state.ghanaCardNumber,
          vehicleMake: state.vehicleMake,
          vehicleModel: state.vehicleModel,
          vehicleYear: state.vehicleYear,
          vehiclePlate: state.vehiclePlate,
          vehicleColor: state.vehicleColor,
        ),
      );
      _auth.completeSignUp(user);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Registration failed. Try again.',
      );
      return false;
    }
  }
}

final driverRegistrationProvider = StateNotifierProvider<
    DriverRegistrationController, DriverRegistrationDraft>((ref) {
  return DriverRegistrationController(
    ref.watch(authRepositoryProvider),
    ref.watch(authControllerProvider.notifier),
  );
});

/// Artisan registration draft.
class ArtisanRegistrationDraft {
  ArtisanRegistrationDraft({
    this.fullName = '',
    this.email = '',
    this.ghanaCardNumber = '',
    this.businessName = '',
    this.tradeCategory = '',
    this.yearsOfExperience = 0,
    this.serviceCategories = const [],
    this.serviceRadiusKm = 5,
    this.isSubmitting = false,
    this.error,
  });

  final String fullName;
  final String email;
  final String ghanaCardNumber;
  final String businessName;
  final String tradeCategory;
  final int yearsOfExperience;
  final List<String> serviceCategories;
  final double serviceRadiusKm;
  final bool isSubmitting;
  final String? error;

  ArtisanRegistrationDraft copyWith({
    String? fullName,
    String? email,
    String? ghanaCardNumber,
    String? businessName,
    String? tradeCategory,
    int? yearsOfExperience,
    List<String>? serviceCategories,
    double? serviceRadiusKm,
    bool? isSubmitting,
    String? error,
    bool clearError = false,
  }) =>
      ArtisanRegistrationDraft(
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        ghanaCardNumber: ghanaCardNumber ?? this.ghanaCardNumber,
        businessName: businessName ?? this.businessName,
        tradeCategory: tradeCategory ?? this.tradeCategory,
        yearsOfExperience: yearsOfExperience ?? this.yearsOfExperience,
        serviceCategories: serviceCategories ?? this.serviceCategories,
        serviceRadiusKm: serviceRadiusKm ?? this.serviceRadiusKm,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        error: clearError ? null : (error ?? this.error),
      );

  bool get isComplete =>
      fullName.isNotEmpty &&
      email.isNotEmpty &&
      ghanaCardNumber.isNotEmpty &&
      businessName.isNotEmpty &&
      tradeCategory.isNotEmpty &&
      serviceCategories.isNotEmpty;
}

class ArtisanRegistrationController
    extends StateNotifier<ArtisanRegistrationDraft> {
  ArtisanRegistrationController(this._repo, this._auth)
      : super(ArtisanRegistrationDraft());

  final AuthRepository _repo;
  final AuthController _auth;

  void update(ArtisanRegistrationDraft draft) => state = draft;

  Future<bool> submit(String phone) async {
    if (!state.isComplete) {
      state = state.copyWith(error: 'Please fill in all required fields.');
      return false;
    }
    state = state.copyWith(isSubmitting: true, clearError: true);
    try {
      final user = await _repo.registerArtisan(
        phone: phone,
        payload: ArtisanRegistrationPayload(
          fullName: state.fullName,
          email: state.email,
          ghanaCardNumber: state.ghanaCardNumber,
          businessName: state.businessName,
          tradeCategory: state.tradeCategory,
          yearsOfExperience: state.yearsOfExperience,
          serviceCategories: state.serviceCategories,
          serviceRadiusKm: state.serviceRadiusKm,
        ),
      );
      _auth.completeSignUp(user);
      state = state.copyWith(isSubmitting: false);
      return true;
    } on AuthException catch (e) {
      state = state.copyWith(isSubmitting: false, error: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        isSubmitting: false,
        error: 'Registration failed. Try again.',
      );
      return false;
    }
  }
}

final artisanRegistrationProvider = StateNotifierProvider<
    ArtisanRegistrationController, ArtisanRegistrationDraft>((ref) {
  return ArtisanRegistrationController(
    ref.watch(authRepositoryProvider),
    ref.watch(authControllerProvider.notifier),
  );
});
