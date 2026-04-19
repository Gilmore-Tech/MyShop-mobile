import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_controller.dart';

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
  factory AccountProfile.fromUserProfile(UserProfile profile) {
    final client = profile.client;
    final displayName = client?.displayName ?? profile.fullName;
    final phone = profile.phone;
    final email = profile.email ?? '';

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

      // TODO: Fetch unread notification count from GET /notifications?unread=true
      // For now derive from auth profile — the notification count will be
      // wired when the notification provider is integrated.
      return AccountScreenData(
        profile: profile,
        unreadNotificationCount: 0,
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
