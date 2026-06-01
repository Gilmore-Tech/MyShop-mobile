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
  /// Phase 3 strict separation (CLAUDE.md §1, §8): visible profile fields
  /// (`legalName`/`email`/`languagePref`) come from the ACTIVE role's
  /// sub-profile only. We do NOT fall back to the root `User.*` fields
  /// because cross-role bleed via that fallback is exactly the bug
  /// Phase 3 fixed: registering Driver with an email then Client without
  /// one used to show the Driver's email on the Client app via the
  /// fallback path. `legalName` falls back to `User.fullName` only when
  /// the role profile literally has no value (defensive — backend
  /// inserts a legalName at registration so this only matters for the
  /// brief window before Phase 3 backfill ran on a per-account basis).
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

    return AuthUser(
      id: profile.id,
      phone: profile.phone,
      // legalName: per-role value; defensive fallback to root only if
      // the role profile literally has none (shouldn't happen post-backfill).
      fullName: roleLegalName ?? profile.fullName,
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

  /// Legal name for the active role. During the Phase 3 transition,
  /// resolved from the role profile's `legalName` when present, falling
  /// back to the root `User.fullName`.
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
