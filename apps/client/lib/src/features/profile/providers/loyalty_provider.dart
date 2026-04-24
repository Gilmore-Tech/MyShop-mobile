import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';

// ── Tier helpers ──────────────────────────────────────────────────────────────

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

LoyaltyTier _parseTier(String? raw) => switch (raw?.toLowerCase()) {
      'silver' => LoyaltyTier.silver,
      'gold'   => LoyaltyTier.gold,
      _        => LoyaltyTier.bronze,
    };

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

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    final pts = (json['points'] as num?)?.toInt() ?? 0;
    final isEarn = pts >= 0;
    return LedgerEntry(
      label:     json['description'] as String? ?? 'Transaction',
      dateLabel: _formatDate(json['createdAt'] as String?),
      points:    pts.abs(),
      isEarn:    isEarn,
    );
  }
}

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
  final int           points;
  final LoyaltyTier   tier;
  final int           lifetimePoints;
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

  double get ghsValue => points / 100.0;

  factory LoyaltyData.fromJson(Map<String, dynamic> json) {
    final ledgerRaw =
        (json['ledger'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    return LoyaltyData(
      points:        (json['points'] as num?)?.toInt() ?? 0,
      tier:          _parseTier(json['tier'] as String?),
      lifetimePoints: (json['lifetimePoints'] as num?)?.toInt() ?? 0,
      ledger:        ledgerRaw.map(LedgerEntry.fromJson).toList(),
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final loyaltyProvider =
    FutureProvider.autoDispose<LoyaltyData>((ref) async {
  try {
    final json = await ref.read(userServiceProvider).getLoyalty();
    return LoyaltyData.fromJson(json);
  } catch (e) {
    developer.log('getLoyalty error: $e', name: 'LoyaltyProvider');
    // Fallback: build from the balance already in the auth state.
    final authState = ref.read(clientAuthControllerProvider);
    int balance = 0;
    if (authState is AuthAuthenticated) {
      balance = authState.profile.client?.loyaltyPointsBalance ?? 0;
    }
    return LoyaltyData(
      points:        balance,
      tier:          _parseTier(null),
      lifetimePoints: balance,
      ledger:        const [],
    );
  }
});
