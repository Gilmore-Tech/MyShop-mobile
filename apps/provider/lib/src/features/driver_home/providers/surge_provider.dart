import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Surge pricing state.
///
/// [surgeMultiplier] is 1.0 when no surge, >1.0 during surge.
/// [isActive] is true when surge multiplier exceeds 1.0.
class SurgeState {
  const SurgeState({
    this.multiplier = 1.0,
    this.zoneName,
  });

  final double multiplier;
  final String? zoneName;

  bool get isActive => multiplier > 1.0;

  String get displayMultiplier => '${multiplier.toStringAsFixed(1)}x';
}

/// Provides current surge pricing info for the driver's area.
final surgeProvider = StateProvider<SurgeState>(
  (ref) => const SurgeState(),
);
