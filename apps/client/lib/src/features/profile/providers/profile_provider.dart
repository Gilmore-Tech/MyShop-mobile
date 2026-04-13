import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Account Profile ───────────────────────────────────────────────────────────
// API: GET /v1/users/me  (EDD § User Endpoints)
// Phone number is the primary identity anchor (EDD § Auth Module).
// Email and phone are masked in-app — backend performs masking before serving.
// KYC status reflects Smile Identity verification (EDD § Verification Module).

class AccountProfile {
  final String userId;
  final String displayName;

  /// Backend-masked email, e.g. "emm*****.b@gmail.com".
  final String maskedEmail;

  /// Backend-masked phone, e.g. "+233 ••• ••• 459".
  final String maskedPhone;

  /// True once Smile Identity KYC (Ghana Card) is approved.
  final bool isKycVerified;

  /// Remote avatar URL — null means show initials placeholder.
  final String? avatarUrl;

  const AccountProfile({
    required this.userId,
    required this.displayName,
    required this.maskedEmail,
    required this.maskedPhone,
    required this.isKycVerified,
    this.avatarUrl,
  });

  /// First two initials for the avatar placeholder.
  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }
}

// ── Account Screen Data ───────────────────────────────────────────────────────

class AccountScreenData {
  final AccountProfile profile;

  /// Unread notification count — drives the "N New" badge on the
  /// Notifications row and the bell dot in the app bar.
  final int unreadNotificationCount;

  const AccountScreenData({
    required this.profile,
    required this.unreadNotificationCount,
  });
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class AccountScreenNotifier
    extends AutoDisposeAsyncNotifier<AccountScreenData> {
  @override
  Future<AccountScreenData> build() async {
    // TODO: GET /v1/users/me  +  GET /v1/notifications?unread=true&count=1
    await Future.delayed(const Duration(milliseconds: 300));
    return _mockData;
  }
}

final accountScreenProvider =
    AsyncNotifierProvider.autoDispose<AccountScreenNotifier, AccountScreenData>(
  AccountScreenNotifier.new,
);

// ── Mock data ─────────────────────────────────────────────────────────────────

const _mockData = AccountScreenData(
  profile: AccountProfile(
    userId:        'USR-10021',
    displayName:   'Emmanuel Boateng',
    maskedEmail:   'emm*****.b@gmail.com',
    maskedPhone:   '+233 ••• ••• 459',
    isKycVerified: true,
  ),
  unreadNotificationCount: 3,
);
