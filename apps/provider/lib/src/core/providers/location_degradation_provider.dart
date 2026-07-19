import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ProviderLocationDegradationState {
  const ProviderLocationDegradationState({
    required this.isDegraded,
    required this.hasActiveWork,
    required this.isOffline,
    this.reasonCode,
    this.degradedAt,
    this.escalatedAt,
  });

  const ProviderLocationDegradationState.healthy()
      : isDegraded = false,
        hasActiveWork = false,
        isOffline = false,
        reasonCode = null,
        degradedAt = null,
        escalatedAt = null;

  factory ProviderLocationDegradationState.fromSnapshot(
    ProviderAvailabilitySnapshot snapshot,
  ) {
    return ProviderLocationDegradationState(
      isDegraded: snapshot.locationRecoveryRequired,
      hasActiveWork: snapshot.hasActiveWork,
      isOffline: snapshot.status == ProviderAvailabilityStatus.offline,
      reasonCode: snapshot.locationDegradedReason,
      degradedAt: snapshot.locationDegradedAt,
      escalatedAt: snapshot.locationDegradedEscalatedAt,
    );
  }

  factory ProviderLocationDegradationState.local({
    required LocationUnavailableReason reason,
    required bool hasActiveWork,
  }) {
    return ProviderLocationDegradationState(
      isDegraded: true,
      hasActiveWork: hasActiveWork,
      isOffline: !hasActiveWork,
      reasonCode: reason.wireValue,
      degradedAt: DateTime.now(),
    );
  }

  final bool isDegraded;
  final bool hasActiveWork;
  final bool isOffline;
  final String? reasonCode;
  final DateTime? degradedAt;
  final DateTime? escalatedAt;

  bool get isEscalated => escalatedAt != null;
}

final providerLocationDegradationProvider =
    StateProvider<ProviderLocationDegradationState>(
  (_) => const ProviderLocationDegradationState.healthy(),
);
