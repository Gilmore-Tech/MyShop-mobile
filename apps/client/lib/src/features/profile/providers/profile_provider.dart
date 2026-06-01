import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_controller.dart';
import '../../notifications/providers/notifications_provider.dart';

// ── Account Profile ───────────────────────────────────��───────────────────────
// API: GET /v1/users/me  (EDD § User Endpoints)

class AccountProfile {
  final String userId;
  final String displayName;
  final String maskedEmail;
  final String maskedPhone;
  final bool isKycVerified;
  final String? avatarUrl;
  final int loyaltyPointsBalance;
  final String? referralCode;

  const AccountProfile({
    required this.userId,
    required this.displayName,
    required this.maskedEmail,
    required this.maskedPhone,
    required this.isKycVerified,
    this.avatarUrl,
    this.loyaltyPointsBalance = 0,
    this.referralCode,
  });

  /// Build from the authenticated user's profile.
  ///
  /// Phase 3 strict separation (CLAUDE.md §1, §8): every visible field is
  /// read from the Client role's sub-profile, NEVER the shared `users.*`
  /// columns. Previously this read root `profile.email`, which leaked the
  /// Driver's email into the Client account page when a user held both
  /// roles on one phone but only set an email on Driver registration.
  factory AccountProfile.fromUserProfile(UserProfile profile) {
    final client = profile.client;
    final displayName = client?.displayName ?? client?.legalName ?? profile.fullName;
    final phone = profile.phone;
    final email = client?.email ?? '';

    return AccountProfile(
      userId: profile.id,
      displayName: displayName,
      maskedEmail: _maskEmail(email),
      maskedPhone: _maskPhone(phone),
      isKycVerified: client?.ghanaCardVerified ?? false,
      avatarUrl: client?.profilePhotoUrl,
      loyaltyPointsBalance: client?.loyaltyPointsBalance ?? 0,
      referralCode: client?.referralCode,
    );
  }

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
  }

  static String _maskPhone(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.length < 6) return phone;
    final prefix = cleaned.substring(0, 4);
    final suffix = cleaned.substring(cleaned.length - 3);
    return '$prefix ••• ••• $suffix';
  }

  static String _maskEmail(String email) {
    if (email.isEmpty) return '';
    final parts = email.split('@');
    if (parts.length != 2) return email;
    final name = parts[0];
    final domain = parts[1];
    if (name.length <= 3) return '${name[0]}***@$domain';
    return '${name.substring(0, 3)}*****@$domain';
  }
}

// ── Account Screen Data ───────────────────────────────────────────────────────

class AccountScreenData {
  final AccountProfile profile;
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
    final authState = ref.watch(clientAuthControllerProvider);

    if (authState is AuthAuthenticated) {
      final profile = AccountProfile.fromUserProfile(authState.profile);

      // Watch the live notifications list and derive the unread count —
      // this provider rebuilds automatically when a push arrives or the
      // user marks one read on the notifications screen, so the badge
      // stays in sync without a separate /notifications/unread call.
      final notifs = ref.watch(notifsProvider);
      final unread = notifs.where((n) => !n.isRead).length;

      return AccountScreenData(
        profile: profile,
        unreadNotificationCount: unread,
      );
    }

    // Fallback — shouldn't normally happen if router guards are working
    throw Exception('Not authenticated');
  }
}

final accountScreenProvider =
    AsyncNotifierProvider.autoDispose<AccountScreenNotifier, AccountScreenData>(
  AccountScreenNotifier.new,
);
