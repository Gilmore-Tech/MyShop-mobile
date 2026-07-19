import '../models/user_dtos.dart';

/// The role of an authenticated user.
enum AuthRole {
  client,
  driver,
  artisan;

  static AuthRole? fromString(String? value) {
    if (value == null) return null;
    return AuthRole.values.where((r) => r.name == value).firstOrNull;
  }
}

/// Authenticated user derived from the backend's UserProfile.
/// This is the app-facing model; the raw [UserProfile] DTO stays internal.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.phone,
    required this.fullName,
    required this.role,
    this.email,
    this.languagePref = 'en',
    this.status = 'active',
    this.driverProfile,
    this.artisanProfile,
    this.clientProfile,
  });

  /// Create an [AuthUser] from a [UserProfile] DTO.
  ///
  /// [activeRole] overrides role detection for dual-role accounts.
  /// When null, falls back to checking which sub-profiles exist
  /// (driver takes priority over artisan for backwards compatibility).
  ///
  /// Visible profile fields (`legalName`/`email`/`languagePref`) come only
  /// from the active role's sub-profile. The top-level profile may have been
  /// produced by an older backend that exposed a shared phone-auth identity,
  /// so it is never a fallback for an absent role value.
  factory AuthUser.fromProfile(UserProfile profile, {AuthRole? activeRole}) {
    final role = activeRole ??
        (profile.driver != null
            ? AuthRole.driver
            : profile.artisan != null
                ? AuthRole.artisan
                : AuthRole.client);

    String? roleLegalName;
    String? roleEmail;
    String? roleLanguagePref;
    switch (role) {
      case AuthRole.driver:
        roleLegalName = profile.driver?.legalName;
        roleEmail = profile.driver?.email;
        roleLanguagePref = profile.driver?.languagePref;
        break;
      case AuthRole.artisan:
        roleLegalName = profile.artisan?.legalName;
        roleEmail = profile.artisan?.email;
        roleLanguagePref = profile.artisan?.languagePref;
        break;
      case AuthRole.client:
        roleLegalName = profile.client?.legalName;
        roleEmail = profile.client?.email;
        roleLanguagePref = profile.client?.languagePref;
        break;
    }

    final roleName = switch (role) {
      AuthRole.driver =>
        roleLegalName ?? profile.driver?.displayName ?? 'Driver',
      AuthRole.artisan => roleLegalName ??
          profile.artisan?.businessName ??
          profile.artisan?.displayName ??
          'Artisan',
      AuthRole.client =>
        roleLegalName ?? profile.client?.displayName ?? 'Client',
    };

    return AuthUser(
      id: profile.id,
      phone: profile.phone,
      fullName: roleName,
      // email: per-role ONLY. Null = user hasn't set one for this role.
      // No fallback to root — that path causes cross-role bleed.
      email: roleEmail,
      // languagePref: per-role only, default 'en' baked into the role DTO.
      languagePref: roleLanguagePref ?? 'en',
      role: role,
      status: profile.status,
      driverProfile: profile.driver,
      artisanProfile: profile.artisan,
      clientProfile: profile.client,
    );
  }

  final String id;
  final String phone;

  /// Name for the active role. Missing role data becomes a neutral role label;
  /// it never falls back to the private phone-auth identity.
  final String fullName;

  /// Email for the active role.
  final String? email;

  /// Language preference for the active role (Twi/English).
  final String languagePref;
  final AuthRole role;
  final String status;
  final DriverProfile? driverProfile;
  final ArtisanProfile? artisanProfile;
  final ClientProfile? clientProfile;

  bool get isDriver => role == AuthRole.driver;
  bool get isArtisan => role == AuthRole.artisan;
  bool get isClient => role == AuthRole.client;

  /// The public-facing display name for the active role.
  /// - **Driver**: always the legal name (fullName)
  /// - **Artisan**: business name first, then display name, then legal name
  /// - **Client**: display name, then legal name
  String get displayName {
    if (isDriver) return fullName;
    if (isArtisan) {
      return artisanProfile?.businessName ??
          artisanProfile?.displayName ??
          fullName;
    }
    if (isClient) return clientProfile?.displayName ?? fullName;
    return fullName;
  }

  /// Profile photo URL for the active role. Each role has its own photo.
  String? get profilePhotoUrl {
    if (isDriver) return driverProfile?.profilePhotoUrl;
    if (isArtisan) return artisanProfile?.profilePhotoUrl;
    if (isClient) return clientProfile?.profilePhotoUrl;
    return null;
  }

  /// The artisan's business/shop name. Null for non-artisan roles.
  String? get businessName => artisanProfile?.businessName;

  String get verificationStatus {
    if (isDriver) return driverProfile?.verificationStatus ?? 'pending';
    if (isArtisan) return artisanProfile?.verificationStatus ?? 'pending';
    return 'approved';
  }
}
