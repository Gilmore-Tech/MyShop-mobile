import '../models/auth_dtos.dart';
import '../models/user_dtos.dart';
import 'auth_service.dart';

/// In-memory mock so the UI can be developed end-to-end without the backend.
///
/// Behaviour:
///   - Any phone number is accepted for register.
///   - The OTP code is always `123456`.
///   - Login succeeds for any previously registered phone.
///   - `getMe()` returns a mock profile for the registered user.
class MockAuthService implements AuthService {
  MockAuthService();

  static const _validCode = '123456';
  final Set<String> _registeredPhones = {};
  String? _lastPhone;
  String? _lastType;

  @override
  Future<void> register(RegisterRequest request) async {
    await _delay();
    _registeredPhones.add(request.phone);
    _lastPhone = request.phone;
    _lastType = request.type;
  }

  @override
  Future<void> loginDriver(String phone) async {
    await _delay();
    if (!_registeredPhones.contains(phone)) {
      throw AuthException(
        'No account found for this phone number. Please register first.',
        code: 'ACCOUNT_NOT_FOUND',
      );
    }
    _lastPhone = phone;
    _lastType = 'driver';
  }

  @override
  Future<void> loginArtisan(String phone) async {
    await _delay();
    if (!_registeredPhones.contains(phone)) {
      throw AuthException(
        'No account found for this phone number. Please register first.',
        code: 'ACCOUNT_NOT_FOUND',
      );
    }
    _lastPhone = phone;
    _lastType = 'artisan';
  }

  @override
  Future<void> loginClient(String phone) async {
    await _delay();
    if (!_registeredPhones.contains(phone)) {
      throw AuthException(
        'No account found for this phone number. Please register first.',
        code: 'ACCOUNT_NOT_FOUND',
      );
    }
    _lastPhone = phone;
    _lastType = 'client';
  }

  @override
  Future<List<String>> checkPhone(String phone) async {
    await _delay();
    if (!_registeredPhones.contains(phone)) {
      throw AuthException(
        'No account found for this phone number. Please register first.',
        code: 'USER_NOT_FOUND',
      );
    }
    // Mock: return the last registered type, or both for testing.
    if (_lastType == 'both') return ['driver', 'artisan'];
    return [_lastType ?? 'driver'];
  }

  @override
  Future<String> login(String phone) async {
    await _delay();
    if (!_registeredPhones.contains(phone)) {
      throw AuthException(
        'No account found for this phone number. Please register first.',
        code: 'ACCOUNT_NOT_FOUND',
      );
    }
    _lastPhone = phone;
    return _lastType ?? 'driver';
  }

  @override
  Future<TokenResponse> verifyOtp(VerifyOtpRequest request) async {
    await _delay();
    if (request.otp != _validCode) {
      throw AuthException('Invalid OTP code.', code: 'INVALID_OTP');
    }
    _registeredPhones.add(request.phone);
    return const TokenResponse(
      accessToken: 'mock_access_token',
      refreshToken: 'mock_refresh_token',
    );
  }

  @override
  Future<String> refreshToken(String refreshToken) async {
    await _delay();
    return 'mock_refreshed_access_token';
  }

  @override
  Future<UserProfile> getMe() async {
    await _delay();
    final phone = _lastPhone ?? '+233241234567';
    final isDriver = _lastType != 'artisan';

    return UserProfile(
      id: 'mock_user_${phone.hashCode}',
      phone: phone,
      fullName: isDriver ? 'Mock Driver' : 'Mock Artisan',
      languagePref: 'en',
      status: 'active',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
      driver: isDriver
          ? const DriverProfile(
              id: 'mock_driver_id',
              ghanaCardVerified: false,
              verificationStatus: 'pending',
              kycStatus: 'not_started',
              policeCheckStatus: 'not_started',
              onlineStatus: 'offline',
              serviceRadiusKm: 5.0,
              payoutPreference: 'instant',
              cancellationCount30d: 0,
            )
          : null,
      artisan: !isDriver
          ? const ArtisanProfile(
              id: 'mock_artisan_id',
              ghanaCardVerified: false,
              verificationStatus: 'pending',
              kycStatus: 'not_started',
              policeCheckStatus: 'not_started',
              onlineStatus: 'offline',
              serviceRadiusKm: 5.0,
              shopCapacity: 'solo',
              maxConcurrentJobs: 1,
              payoutPreference: 'instant',
              completedJobsCount: 0,
              cancellationCount30d: 0,
            )
          : null,
    );
  }

  @override
  Future<UserProfile> updateMe(UpdateProfileRequest request) async {
    await _delay();
    final current = await getMe();
    return UserProfile(
      id: current.id,
      phone: current.phone,
      fullName: request.fullName ?? current.fullName,
      email: request.email ?? current.email,
      languagePref: request.languagePref ?? current.languagePref,
      status: current.status,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
      driver: current.driver,
      artisan: current.artisan,
    );
  }

  @override
  Future<UserProfile> updateDriver(UpdateDriverProfileRequest request) async {
    await _delay();
    final current = await getMe();
    final dp = current.driver;
    return UserProfile(
      id: current.id,
      phone: current.phone,
      fullName: current.fullName,
      email: current.email,
      languagePref: current.languagePref,
      status: current.status,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
      driver: dp != null
          ? DriverProfile(
              id: dp.id,
              ghanaCardVerified: dp.ghanaCardVerified,
              profilePhotoUrl: dp.profilePhotoUrl,
              vehicleMake: request.vehicleMake ?? dp.vehicleMake,
              vehicleModel: request.vehicleModel ?? dp.vehicleModel,
              vehicleYear: request.vehicleYear ?? dp.vehicleYear,
              vehiclePlate: request.vehiclePlate ?? dp.vehiclePlate,
              vehicleColor: request.vehicleColor ?? dp.vehicleColor,
              verificationStatus: dp.verificationStatus,
              kycStatus: dp.kycStatus,
              policeCheckStatus: dp.policeCheckStatus,
              onlineStatus: dp.onlineStatus,
              serviceRadiusKm:
                  request.serviceRadiusKm ?? dp.serviceRadiusKm,
              payoutPreference:
                  request.payoutPreference ?? dp.payoutPreference,
              payoutMethod: request.payoutMethod ?? dp.payoutMethod,
              payoutAccountNumber:
                  request.payoutAccountNumber ?? dp.payoutAccountNumber,
              licenceNumber: request.licenceNumber ?? dp.licenceNumber,
              licenceExpiry: request.licenceExpiry ?? dp.licenceExpiry,
              cancellationCount30d: dp.cancellationCount30d,
            )
          : null,
      artisan: current.artisan,
    );
  }

  @override
  Future<UserProfile> updateArtisan(UpdateArtisanProfileRequest request) async {
    await _delay();
    final current = await getMe();
    final ap = current.artisan;
    return UserProfile(
      id: current.id,
      phone: current.phone,
      fullName: current.fullName,
      email: current.email,
      languagePref: current.languagePref,
      status: current.status,
      createdAt: current.createdAt,
      updatedAt: DateTime.now().toIso8601String(),
      driver: current.driver,
      artisan: ap != null
          ? ArtisanProfile(
              id: ap.id,
              displayName: request.displayName ?? ap.displayName,
              businessName: request.businessName ?? ap.businessName,
              ghanaCardVerified: ap.ghanaCardVerified,
              profilePhotoUrl: ap.profilePhotoUrl,
              verificationStatus: ap.verificationStatus,
              kycStatus: ap.kycStatus,
              policeCheckStatus: ap.policeCheckStatus,
              onlineStatus: ap.onlineStatus,
              serviceRadiusKm:
                  request.serviceRadiusKm ?? ap.serviceRadiusKm,
              shopCapacity: request.shopCapacity ?? ap.shopCapacity,
              maxConcurrentJobs:
                  request.maxConcurrentJobs ?? ap.maxConcurrentJobs,
              payoutPreference:
                  request.payoutPreference ?? ap.payoutPreference,
              payoutMethod: request.payoutMethod ?? ap.payoutMethod,
              payoutAccountNumber:
                  request.payoutAccountNumber ?? ap.payoutAccountNumber,
              completedJobsCount: ap.completedJobsCount,
              cancellationCount30d: ap.cancellationCount30d,
              serviceCategories: ap.serviceCategories,
            )
          : null,
    );
  }

  Future<void> _delay() =>
      Future<void>.delayed(const Duration(milliseconds: 600));
}
