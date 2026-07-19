import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_controller.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class SpecialOffer {
  final String id;
  final String tag;
  final String title;
  final String subtitle;
  final String? promoCode;
  final Color backgroundColor;

  const SpecialOffer({
    required this.id,
    required this.tag,
    required this.title,
    required this.subtitle,
    this.promoCode,
    required this.backgroundColor,
  });
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Special offers — in production these come from a config/promo endpoint.
/// For pilot, we keep a small static set that can be updated via platform config.
final specialOffersProvider =
    AsyncNotifierProvider<SpecialOffersNotifier, List<SpecialOffer>>(
  SpecialOffersNotifier.new,
);

class SpecialOffersNotifier extends AsyncNotifier<List<SpecialOffer>> {
  @override
  Future<List<SpecialOffer>> build() async {
    // Emergency release containment: do not advertise static codes while the
    // server-side promo redemption path is suspended. Re-enable from an
    // authoritative runtime endpoint only after atomic reservation is proven.
    return const [];
  }
}

/// User's display name from auth state — used in the greeting.
final userDisplayNameProvider = Provider<String>((ref) {
  final authState = ref.watch(clientAuthControllerProvider);
  if (authState is AuthAuthenticated) {
    final client = authState.profile.client;
    return client?.displayName ?? authState.profile.fullName;
  }
  return 'there';
});
