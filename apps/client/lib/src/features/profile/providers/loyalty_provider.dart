import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';

// ── Tier helpers ──────────────────────────────────────────────────────────────
// Tier breakpoints are presentation-only — the backend doesn't expose a
// 'tier' field, it just tracks raw points. If pilot data shows different
// thresholds work better, change these without touching the API.

enum LoyaltyTier { bronze, silver, gold }

extension LoyaltyTierX on LoyaltyTier {
  String get label => switch (this) {
        LoyaltyTier.bronze => 'Bronze Member',
        LoyaltyTier.silver => 'Silver Member',
        LoyaltyTier.gold   => 'Gold Member',
      };

  int get minPoints => switch (this) {
        LoyaltyTier.bronze => 0,
        LoyaltyTier.silver => 500,
        LoyaltyTier.gold   => 2000,
      };

  int get maxPoints => switch (this) {
        LoyaltyTier.bronze => 499,
        LoyaltyTier.silver => 1999,
        LoyaltyTier.gold   => 999999,
      };
}

LoyaltyTier _tierFromPoints(int points) {
  if (points >= LoyaltyTier.gold.minPoints) return LoyaltyTier.gold;
  if (points >= LoyaltyTier.silver.minPoints) return LoyaltyTier.silver;
  return LoyaltyTier.bronze;
}

// ── Ledger entry ──────────────────────────────────────────────────────────────

class LedgerEntry {
  final String label;
  final String dateLabel;
  final int    points;
  final bool   isEarn;

  const LedgerEntry({
    required this.label,
    required this.dateLabel,
    required this.points,
    required this.isEarn,
  });

  /// Maps a backend `loyalty_transactions` row into the UI shape.
  /// Backend columns we read:
  ///   transactionType: 'earned_ride' | 'earned_job' | 'earned_referral' |
  ///                    'redeemed' | 'expired' | 'adjusted'
  ///   points:          signed int — positive earn, negative redeem/expire
  ///   description:     free-text from the backend, may be null
  ///   createdAt:       ISO timestamp
  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    final pts    = (json['points'] as num?)?.toInt() ?? 0;
    final txType = json['transactionType'] as String? ?? '';
    final desc   = (json['description'] as String?)?.trim();

    return LedgerEntry(
      label:     desc != null && desc.isNotEmpty
          ? desc
          : _labelForTransactionType(txType),
      dateLabel: _formatDate(json['createdAt'] as String?),
      points:    pts.abs(),
      isEarn:    pts >= 0,
    );
  }
}

String _labelForTransactionType(String type) => switch (type) {
      'earned_ride'     => 'Ride completed',
      'earned_job'      => 'Job completed',
      'earned_referral' => 'Referral bonus',
      'redeemed'        => 'Points redeemed',
      'expired'         => 'Points expired',
      'adjusted'        => 'Balance adjusted',
      _                 => 'Transaction',
    };

String _formatDate(String? iso) {
  if (iso == null) return '';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return '';
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inDays == 0) return 'Today';
  if (diff.inDays == 1) return 'Yesterday';
  const months = ['Jan','Feb','Mar','Apr','May','Jun',
                   'Jul','Aug','Sep','Oct','Nov','Dec'];
  return '${months[dt.month - 1]} ${dt.day}';
}

// ── Loyalty data ──────────────────────────────────────────────────────────────

class LoyaltyData {
  final int               points;
  final LoyaltyTier       tier;
  final int               lifetimePoints;
  final List<LedgerEntry> ledger;

  const LoyaltyData({
    required this.points,
    required this.tier,
    required this.lifetimePoints,
    required this.ledger,
  });

  double get tierProgress {
    final t = tier;
    if (t == LoyaltyTier.gold) return 1.0;
    final range = t.maxPoints - t.minPoints + 1;
    return (points - t.minPoints).clamp(0, range) / range;
  }

  int get pointsToNextTier {
    if (tier == LoyaltyTier.gold) return 0;
    final next = tier == LoyaltyTier.bronze
        ? LoyaltyTier.silver
        : LoyaltyTier.gold;
    return (next.minPoints - points).clamp(0, 999999);
  }

  /// 1 point ≈ 1 pesewa (i.e. 100 points = GH¢ 1) — matches the platform-
  /// config constant `loyalty_ghs_per_point_pesewas` used for redemptions.
  /// Drives the "≈ GH¢ X.XX" hint on the balance card.
  double get ghsValue => points / 100.0;
}

// ── Provider ──────────────────────────────────────────────────────────────────
//
// Pulls the current balance from the in-memory auth profile and the
// transaction history from /v1/loyalty/transactions. Tier is derived
// locally from the balance — backend doesn't expose a tier field.
//
// Lifetime points: sum of every positive ledger entry on the first page.
// Backend doesn't expose a separate "lifetime" counter, so this is a
// good-enough approximation for the badge on the screen. If the user's
// history is longer than `limit`, the number understates — that's
// acceptable for an MVP marketing surface.

final loyaltyProvider =
    FutureProvider.autoDispose<LoyaltyData>((ref) async {
  final authState = ref.watch(clientAuthControllerProvider);
  final balance = authState is AuthAuthenticated
      ? (authState.profile.client?.loyaltyPointsBalance ?? 0)
      : 0;

  List<LedgerEntry> ledger = const [];
  int lifetime = balance;
  try {
    final json = await ref
        .read(loyaltyServiceProvider)
        .getTransactions(page: 1, limit: 30);
    final items = (json['items'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();
    ledger = items.map(LedgerEntry.fromJson).toList();

    // Lifetime ≈ sum of earned points across the visible window. Better
    // than just current balance (which doesn't account for past redemptions).
    final earned = ledger.where((e) => e.isEarn).fold<int>(
          0,
          (sum, e) => sum + e.points,
        );
    if (earned > lifetime) lifetime = earned;
  } catch (e) {
    // History fetch failed (offline, or first launch with no transactions
    // yet). Fall through with an empty ledger — the screen still renders
    // balance + tier + earn-tutorial + redeem-tutorial sections.
    developer.log('getTransactions error: $e', name: 'LoyaltyProvider');
  }

  return LoyaltyData(
    points:         balance,
    tier:           _tierFromPoints(balance),
    lifetimePoints: lifetime,
    ledger:         ledger,
  );
});
