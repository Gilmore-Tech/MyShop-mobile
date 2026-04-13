/// DTOs for user profile endpoints.
/// Matches the contract in `docs/mobile-api-endpoints.md`.

/// Full user profile from GET /users/me.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.languagePref,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.email,
    this.privacyPolicyAcceptedAt,
    this.deletedAt,
    this.recoveryDeadline,
    this.client,
    this.driver,
    this.artisan,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      phone: json['phone'] as String,
      fullName: json['fullName'] as String,
      email: json['email'] as String?,
      languagePref: json['languagePref'] as String,
      status: json['status'] as String,
      privacyPolicyAcceptedAt: json['privacyPolicyAcceptedAt'] as String?,
      deletedAt: json['deletedAt'] as String?,
      recoveryDeadline: json['recoveryDeadline'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      client: json['client'] != null
          ? ClientProfile.fromJson(json['client'] as Map<String, dynamic>)
          : null,
      driver: json['driver'] != null
          ? DriverProfile.fromJson(json['driver'] as Map<String, dynamic>)
          : null,
      artisan: json['artisan'] != null
          ? ArtisanProfile.fromJson(json['artisan'] as Map<String, dynamic>)
          : null,
    );
  }

  final String id;
  final String phone;
  final String fullName;
  final String? email;
  final String languagePref;
  final String status;
  final String? privacyPolicyAcceptedAt;
  final String? deletedAt;
  final String? recoveryDeadline;
  final String createdAt;
  final String updatedAt;
  final ClientProfile? client;
  final DriverProfile? driver;
  final ArtisanProfile? artisan;

  /// Returns the primary role based on which sub-profile is non-null.
  String? get primaryRole {
    if (driver != null) return 'driver';
    if (artisan != null) return 'artisan';
    if (client != null) return 'client';
    return null;
  }
}

/// Client sub-profile from GET /users/me.
class ClientProfile {
  const ClientProfile({
    required this.id,
    required this.loyaltyPointsBalance,
    required this.ghanaCardVerified,
    this.displayName,
    this.profilePhotoUrl,
    this.referralCode,
    this.preferredPaymentMethod,
  });

  factory ClientProfile.fromJson(Map<String, dynamic> json) {
    return ClientProfile(
      id: json['id'] as String,
      displayName: _asString(json['displayName']),
      profilePhotoUrl: _asString(json['profilePhotoUrl']),
      loyaltyPointsBalance: json['loyaltyPointsBalance'] as int? ?? 0,
      referralCode: _asString(json['referralCode']),
      preferredPaymentMethod: _asString(json['preferredPaymentMethod']),
      ghanaCardVerified: json['ghanaCardVerified'] as bool? ?? false,
    );
  }

  final String id;

  /// Public-facing name for this role. Falls back to [UserProfile.fullName].
  final String? displayName;

  /// Profile photo specific to the client role.
  final String? profilePhotoUrl;

  final int loyaltyPointsBalance;
  final String? referralCode;
  final String? preferredPaymentMethod;
  final bool ghanaCardVerified;
}

/// Driver sub-profile from GET /users/me.
class DriverProfile {
  const DriverProfile({
    required this.id,
    required this.verificationStatus,
    required this.kycStatus,
    required this.policeCheckStatus,
    required this.onlineStatus,
    required this.serviceRadiusKm,
    required this.payoutPreference,
    required this.cancellationCount30d,
    required this.ghanaCardVerified,
    this.displayName,
    this.profilePhotoUrl,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleYear,
    this.vehiclePlate,
    this.vehicleColor,
    this.licenceNumber,
    this.licenceExpiry,
    this.payoutMethod,
    this.payoutAccountNumber,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    return DriverProfile(
      id: json['id'] as String,
      displayName: _asString(json['displayName']),
      ghanaCardVerified: json['ghanaCardVerified'] as bool? ?? false,
      profilePhotoUrl: _asString(json['profilePhotoUrl']),
      vehicleMake: _asString(json['vehicleMake']),
      vehicleModel: _asString(json['vehicleModel']),
      vehicleYear: _asString(json['vehicleYear']),
      vehiclePlate: _asString(json['vehiclePlate']),
      vehicleColor: _asString(json['vehicleColor']),
      verificationStatus: _asString(json['verificationStatus']) ?? 'pending',
      kycStatus: _asString(json['kycStatus']) ?? 'pending',
      policeCheckStatus: _asString(json['policeCheckStatus']) ?? 'pending',
      onlineStatus: _asString(json['onlineStatus']) ?? 'offline',
      serviceRadiusKm: _parseDouble(json['serviceRadiusKm']),
      payoutPreference: _asString(json['payoutPreference']) ?? 'standard',
      payoutMethod: _asString(json['payoutMethod']),
      payoutAccountNumber: _asString(json['payoutAccountNumber']),
      licenceNumber: _asString(json['licenceNumber']),
      licenceExpiry: _asString(json['licenceExpiry']),
      cancellationCount30d: json['cancellationCount30d'] as int? ?? 0,
    );
  }

  final String id;

  /// Public-facing name for this role. Falls back to [UserProfile.fullName].
  final String? displayName;

  final bool ghanaCardVerified;
  final String? profilePhotoUrl;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleYear;
  final String? vehiclePlate;
  final String? vehicleColor;
  final String verificationStatus;
  final String kycStatus;
  final String policeCheckStatus;
  final String onlineStatus;
  final double serviceRadiusKm;
  final String payoutPreference;
  final String? payoutMethod;
  final String? payoutAccountNumber;
  final String? licenceNumber;
  final String? licenceExpiry;
  final int cancellationCount30d;
}

/// Artisan sub-profile from GET /users/me.
class ArtisanProfile {
  const ArtisanProfile({
    required this.id,
    required this.verificationStatus,
    required this.kycStatus,
    required this.policeCheckStatus,
    required this.onlineStatus,
    required this.serviceRadiusKm,
    required this.shopCapacity,
    required this.maxConcurrentJobs,
    required this.payoutPreference,
    required this.completedJobsCount,
    required this.cancellationCount30d,
    required this.ghanaCardVerified,
    this.displayName,
    this.businessName,
    this.profilePhotoUrl,
    this.payoutMethod,
    this.payoutAccountNumber,
    this.serviceCategories,
  });

  factory ArtisanProfile.fromJson(Map<String, dynamic> json) {
    return ArtisanProfile(
      id: json['id'] as String,
      displayName: _asString(json['displayName']),
      businessName: _asString(json['businessName']),
      ghanaCardVerified: json['ghanaCardVerified'] as bool? ?? false,
      profilePhotoUrl: _asString(json['profilePhotoUrl']),
      verificationStatus: _asString(json['verificationStatus']) ?? 'pending',
      kycStatus: _asString(json['kycStatus']) ?? 'pending',
      policeCheckStatus: _asString(json['policeCheckStatus']) ?? 'pending',
      onlineStatus: _asString(json['onlineStatus']) ?? 'offline',
      serviceRadiusKm: _parseDouble(json['serviceRadiusKm']),
      shopCapacity: _asString(json['shopCapacity']) ?? 'solo',
      maxConcurrentJobs: json['maxConcurrentJobs'] as int? ?? 1,
      payoutPreference: _asString(json['payoutPreference']) ?? 'standard',
      payoutMethod: _asString(json['payoutMethod']),
      payoutAccountNumber: _asString(json['payoutAccountNumber']),
      completedJobsCount: json['completedJobsCount'] as int? ?? 0,
      cancellationCount30d: json['cancellationCount30d'] as int? ?? 0,
      serviceCategories: (json['serviceCategories'] as List<dynamic>?)
          ?.map((e) => ServiceCategoryLink.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final String id;

  /// Public-facing name for this role. Falls back to [UserProfile.fullName].
  final String? displayName;

  /// The artisan's trade/business name (e.g. "Bright Spark Electrical").
  /// Distinct from [UserProfile.fullName] which is the person's legal name.
  final String? businessName;

  final bool ghanaCardVerified;
  final String? profilePhotoUrl;
  final String verificationStatus;
  final String kycStatus;
  final String policeCheckStatus;
  final String onlineStatus;
  final double serviceRadiusKm;
  final String shopCapacity;
  final int maxConcurrentJobs;
  final String payoutPreference;
  final String? payoutMethod;
  final String? payoutAccountNumber;
  final int completedJobsCount;
  final int cancellationCount30d;
  final List<ServiceCategoryLink>? serviceCategories;
}

/// Link between an artisan and a service category.
class ServiceCategoryLink {
  const ServiceCategoryLink({
    required this.categoryId,
    required this.category,
  });

  factory ServiceCategoryLink.fromJson(Map<String, dynamic> json) {
    return ServiceCategoryLink(
      categoryId: json['categoryId'] as String,
      category:
          ServiceCategory.fromJson(json['category'] as Map<String, dynamic>),
    );
  }

  final String categoryId;
  final ServiceCategory category;
}

/// A service category (e.g. Plumbing, Electrician).
///
/// Top-level categories may have [children] (one level deep).
/// When registering an artisan, send the leaf category [id] — use a
/// subcategory id (not the parent) for grouped services like Repairs.
class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.name,
    required this.slug,
    this.isActive = true,
    this.minBidPesewas,
    this.children = const [],
  });

  factory ServiceCategory.fromJson(Map<String, dynamic> json) {
    return ServiceCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      slug: json['slug'] as String,
      minBidPesewas: json['minBidPesewas'] as int?,
      isActive: json['isActive'] as bool? ?? true,
      children: (json['children'] as List<dynamic>?)
              ?.map((e) => ServiceCategory.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  final String id;
  final String name;
  final String slug;
  final int? minBidPesewas;
  final bool isActive;
  final List<ServiceCategory> children;

  bool get hasChildren => children.isNotEmpty;
}

/// PUT /users/me request body.
///
/// Send only the fields that changed — omitted fields are left unchanged.
class UpdateProfileRequest {
  const UpdateProfileRequest({
    this.fullName,
    this.email,
    this.languagePref,
  });

  final String? fullName;
  final String? email;
  final String? languagePref;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (fullName != null) json['fullName'] = fullName;
    if (email != null) json['email'] = email;
    if (languagePref != null) json['languagePref'] = languagePref;
    return json;
  }
}

/// PUT /users/me/driver request body.
///
/// Updates driver-specific profile fields (display name, vehicle, licence, etc.).
class UpdateDriverProfileRequest {
  const UpdateDriverProfileRequest({
    this.displayName,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleYear,
    this.vehiclePlate,
    this.vehicleColor,
    this.licenceNumber,
    this.licenceExpiry,
    this.serviceRadiusKm,
    this.payoutPreference,
    this.payoutMethod,
    this.payoutAccountNumber,
  });

  final String? displayName;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleYear;
  final String? vehiclePlate;
  final String? vehicleColor;
  final String? licenceNumber;
  final String? licenceExpiry;
  final double? serviceRadiusKm;
  final String? payoutPreference;
  final String? payoutMethod;
  final String? payoutAccountNumber;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (displayName != null) json['displayName'] = displayName;
    if (vehicleMake != null) json['vehicleMake'] = vehicleMake;
    if (vehicleModel != null) json['vehicleModel'] = vehicleModel;
    if (vehicleYear != null) json['vehicleYear'] = vehicleYear;
    if (vehiclePlate != null) json['vehiclePlate'] = vehiclePlate;
    if (vehicleColor != null) json['vehicleColor'] = vehicleColor;
    if (licenceNumber != null) json['licenceNumber'] = licenceNumber;
    if (licenceExpiry != null) json['licenceExpiry'] = licenceExpiry;
    if (serviceRadiusKm != null) json['serviceRadiusKm'] = serviceRadiusKm;
    if (payoutPreference != null) json['payoutPreference'] = payoutPreference;
    if (payoutMethod != null) json['payoutMethod'] = payoutMethod;
    if (payoutAccountNumber != null) {
      json['payoutAccountNumber'] = payoutAccountNumber;
    }
    return json;
  }
}

/// PUT /users/me/artisan request body.
///
/// Updates artisan-specific profile fields (display name, business, payout, etc.).
class UpdateArtisanProfileRequest {
  const UpdateArtisanProfileRequest({
    this.displayName,
    this.businessName,
    this.shopCapacity,
    this.maxConcurrentJobs,
    this.serviceRadiusKm,
    this.payoutPreference,
    this.payoutMethod,
    this.payoutAccountNumber,
  });

  final String? displayName;
  final String? businessName;
  final String? shopCapacity;
  final int? maxConcurrentJobs;
  final double? serviceRadiusKm;
  final String? payoutPreference;
  final String? payoutMethod;
  final String? payoutAccountNumber;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (displayName != null) json['displayName'] = displayName;
    if (businessName != null) json['businessName'] = businessName;
    if (shopCapacity != null) json['shopCapacity'] = shopCapacity;
    if (maxConcurrentJobs != null) {
      json['maxConcurrentJobs'] = maxConcurrentJobs;
    }
    if (serviceRadiusKm != null) json['serviceRadiusKm'] = serviceRadiusKm;
    if (payoutPreference != null) json['payoutPreference'] = payoutPreference;
    if (payoutMethod != null) json['payoutMethod'] = payoutMethod;
    if (payoutAccountNumber != null) {
      json['payoutAccountNumber'] = payoutAccountNumber;
    }
    return json;
  }
}

/// Safely parse a value that may be a String, int, or double into a double.
/// The backend returns serviceRadiusKm as a string (e.g. "5").
double _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.parse(value);
  return 0.0;
}

/// Safely convert a value that may be a String or int to a String?.
/// Handles backend inconsistencies (e.g. vehicleYear sent as 2022 instead of "2022").
String? _asString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}
