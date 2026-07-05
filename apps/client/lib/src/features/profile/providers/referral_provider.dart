import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';

// ── Referral entry ────────────────────────────────────────────────────────────

class ReferralEntry {
  final String name;
  final String dateLabel;
  final String status;
  final int bonusPesewas;

  const ReferralEntry({
    required this.name,
    required this.dateLabel,
    required this.status,
    required this.bonusPesewas,
  });

  factory ReferralEntry.fromJson(Map<String, dynamic> json) {
    return ReferralEntry(
      name: json['name'] as String? ?? 'Unknown',
      dateLabel: _formatDate(json['createdAt'] as String?),
      status: json['status'] as String? ?? 'pending',
      bonusPesewas: (json['bonusPesewas'] as num?)?.toInt() ?? 0,
    );
  }
}

String _formatDate(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${months[dt.month - 1]} ${dt.day}';
}

// ── Referral data ─────────────────────────────────────────────────────────────

class ReferralData {
  final String code;
  final String? shareLink;
  final int totalReferrals;
  final int pendingPesewas;
  final int earnedPesewas;
  final List<ReferralEntry> recentReferrals;

  const ReferralData({
    required this.code,
    this.shareLink,
    required this.totalReferrals,
    required this.pendingPesewas,
    required this.earnedPesewas,
    required this.recentReferrals,
  });

  double get pendingGhs => pendingPesewas / 100.0;
  double get earnedGhs => earnedPesewas / 100.0;

  factory ReferralData.fromJson(Map<String, dynamic> json) {
    final rawList = (json['recentReferrals'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    return ReferralData(
      code: json['code'] as String? ?? '',
      shareLink: json['shareLink'] as String?,
      totalReferrals: (json['totalReferrals'] as num?)?.toInt() ?? 0,
      pendingPesewas: (json['pendingPesewas'] as num?)?.toInt() ?? 0,
      earnedPesewas: (json['earnedPesewas'] as num?)?.toInt() ?? 0,
      recentReferrals: rawList.map(ReferralEntry.fromJson).toList(),
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final referralProvider = FutureProvider.autoDispose<ReferralData>((ref) async {
  try {
    final json = await ref.read(userServiceProvider).getReferral();
    return ReferralData.fromJson(json);
  } catch (e) {
    developer.log('getReferral error: $e', name: 'ReferralProvider');
    // Fallback: use referral code already in the auth state.
    final authState = ref.read(clientAuthControllerProvider);
    String code = '';
    if (authState is AuthAuthenticated) {
      code = authState.profile.client?.referralCode ?? '';
    }
    return ReferralData(
      code: code,
      shareLink: null,
      totalReferrals: 0,
      pendingPesewas: 0,
      earnedPesewas: 0,
      recentReferrals: const [],
    );
  }
});
