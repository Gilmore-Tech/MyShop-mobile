import 'package:api_client/api_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/providers/auth_controller.dart';
import '../services/provider_request_policy.dart';

enum ProviderLocationRejectionKind { locationSession, eligibility }

/// A server-authoritative rejection that cannot be repaired by immediately
/// posting the same provider location sample again.
class ProviderLocationRejection {
  const ProviderLocationRejection({
    required this.kind,
    required this.reasonCodes,
    this.hasUnrecognizedReason = false,
    this.requestBlockMessage,
  });

  final ProviderLocationRejectionKind kind;
  final List<String> reasonCodes;
  final bool hasUnrecognizedReason;

  /// Safe app-authored copy retained from an exact server request-block code.
  /// This lets terminal Online-session recovery explain the real enforcement
  /// reason instead of replacing it with a generic location-session warning.
  final String? requestBlockMessage;
}

/// In-memory fence for a terminal rejection of one exact auth SID and Online
/// epoch. Keeping this outside the background writer preserves the fence when
/// provider status changes rebuild that writer; it is discarded automatically
/// as soon as either authority value changes.
class ProviderLocationSyncPause {
  const ProviderLocationSyncPause({
    required this.authSession,
    required this.onlineSessionId,
    required this.rejection,
  });

  final AuthSessionIdentity authSession;
  final String onlineSessionId;
  final ProviderLocationRejection rejection;

  bool matches(AuthSessionIdentity session, String epoch) =>
      authSession == session && onlineSessionId == epoch;
}

final providerLocationSyncPauseProvider =
    StateProvider<ProviderLocationSyncPause?>((ref) {
  // Scope this in-memory fence to the exact authenticated SID. Riverpod
  // rebuilds it to null on logout, takeover, or role/account replacement.
  ref.watch(currentAuthSessionIdentityProvider);
  return null;
});

const Set<String> _locationSessionReasons = <String>{
  'DRIVER_ONLINE_SESSION_REQUIRED',
  'ARTISAN_ONLINE_SESSION_REQUIRED',
};

// A later device fix can repair these reasons. They remain retryable, but the
// bounded gate below prevents a burst of posts while GPS settles.
const Set<String> _repairableLocationReasons = <String>{
  'GPS_REQUIRED',
  'GPS_LOCATION_STALE',
  'GPS_ACCURACY_INSUFFICIENT',
};

// These are the current provider-eligibility contract reasons that need a new
// Online session or an explicit provider/admin action. Reposting the same GPS
// sample cannot repair them.
const Set<String> _persistentEligibilityReasons = <String>{
  'ROLE_ACCOUNT_NOT_ACTIVE',
  'PROVIDER_APPROVAL_REQUIRED',
  'RM_FINAL_APPROVAL_REQUIRED',
  'VEHICLE_SELECTION_REQUIRED',
  'VEHICLE_NOT_AVAILABLE',
  'VEHICLE_RIDE_CATEGORY_NOT_APPROVED',
  'ACTIVE_VEHICLE_CHANGE_REQUIRES_OFFLINE',
  'LEGACY_VEHICLE_BACKFILL_REQUIRED',
  'DOCUMENT_MISSING_GHANA_CARD',
  'DOCUMENT_NOT_APPROVED_GHANA_CARD',
  'DOCUMENT_MISSING_DRIVERS_LICENCE',
  'DOCUMENT_NOT_APPROVED_DRIVERS_LICENCE',
  'DOCUMENT_EXPIRY_MISSING_DRIVERS_LICENCE',
  'DOCUMENT_EXPIRED_DRIVERS_LICENCE',
  'DOCUMENT_MISSING_PROFILE_PHOTO',
  'DOCUMENT_NOT_APPROVED_PROFILE_PHOTO',
  'VEHICLE_DOCUMENT_MISSING_ROADWORTHINESS',
  'VEHICLE_DOCUMENT_NOT_APPROVED_ROADWORTHINESS',
  'VEHICLE_DOCUMENT_EXPIRY_MISSING_ROADWORTHINESS',
  'VEHICLE_DOCUMENT_EXPIRED_ROADWORTHINESS',
  'VEHICLE_DOCUMENT_MISSING_INSURANCE',
  'VEHICLE_DOCUMENT_NOT_APPROVED_INSURANCE',
  'VEHICLE_DOCUMENT_EXPIRY_MISSING_INSURANCE',
  'VEHICLE_DOCUMENT_EXPIRED_INSURANCE',
  'ARTISAN_TRADE_CREDENTIAL_MISSING',
  'ARTISAN_TRADE_CREDENTIAL_XOR_CONFLICT',
  'ARTISAN_TRADE_CREDENTIAL_NOT_APPROVED',
  'DOCUMENT_REPLACEMENT_GRACE_EXPIRED',
  'LOCATION_DEGRADED',
  'LIVE_DISPATCH_DISABLED',
};

const Set<String> _repairableEligibilityReasons = <String>{
  // Device registration is asynchronous during provider-app startup. A short,
  // bounded retry lets the current SID's registration land without treating a
  // capability-only race as a permanent provider eligibility failure.
  'OFFER_RECEIPT_CAPABILITY_REQUIRED',
};

const Set<String> _directLocationSessionErrors = <String>{
  'PROVIDER_LOCATION_SESSION_REQUIRED',
  'PROVIDER_SESSION_EXPIRED',
  'DRIVER_ONLINE_SESSION_REQUIRED',
  'ARTISAN_ONLINE_SESSION_REQUIRED',
};

const Set<String> _directPersistentEligibilityErrors = <String>{
  'ACCOUNT_SUSPENDED',
  'NOT_VERIFIED',
  'NOTIFICATION_REACHABILITY_REQUIRED',
  'DRIVER_PROFILE_REQUIRED',
  'ARTISAN_PROFILE_REQUIRED',
  'APP_UPDATE_REQUIRED',
};

/// Classifies only responses for which another immediate location write is
/// known to be futile. Unknown/malformed eligibility reason sets fail closed;
/// this prevents a new backend requirement from silently recreating a hot
/// retry loop in an older app.
ProviderLocationRejection? classifyProviderLocationRejection(
  ApiException error,
) {
  final directCode = error.errorCode;
  if (isProviderRequestBlock(error)) {
    return ProviderLocationRejection(
      kind: ProviderLocationRejectionKind.eligibility,
      reasonCodes: <String>[directCode!],
      requestBlockMessage: providerRequestBlockMessage(error),
    );
  }
  if (_directLocationSessionErrors.contains(directCode)) {
    return ProviderLocationRejection(
      kind: ProviderLocationRejectionKind.locationSession,
      reasonCodes: <String>[directCode!],
    );
  }
  if (_directPersistentEligibilityErrors.contains(directCode)) {
    return ProviderLocationRejection(
      kind: ProviderLocationRejectionKind.eligibility,
      reasonCodes: <String>[directCode!],
    );
  }
  if (directCode != 'PROVIDER_NOT_ELIGIBLE') return null;

  final rawReasons = error.details?['reasonCodes'];
  if (rawReasons is! List) {
    return const ProviderLocationRejection(
      kind: ProviderLocationRejectionKind.eligibility,
      reasonCodes: <String>[],
      hasUnrecognizedReason: true,
    );
  }

  final suppliedReasons = <String>{};
  var hasMalformedReason = false;
  for (final value in rawReasons) {
    if (value is! String) {
      hasMalformedReason = true;
      continue;
    }
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9_]{1,80}$').hasMatch(normalized)) {
      hasMalformedReason = true;
      continue;
    }
    suppliedReasons.add(normalized);
  }

  final recognizedReasons = <String>{
    ..._locationSessionReasons,
    ..._repairableLocationReasons,
    ..._repairableEligibilityReasons,
    ..._persistentEligibilityReasons,
  };
  final hasUnknownReason = hasMalformedReason ||
      suppliedReasons.isEmpty ||
      suppliedReasons.difference(recognizedReasons).isNotEmpty;
  final persistentReasons = suppliedReasons.intersection(
    _persistentEligibilityReasons,
  );
  final sessionReasons = suppliedReasons.intersection(_locationSessionReasons);

  // Persistent, malformed, and mixed unknown responses pause the epoch even
  // when they also contain a repairable/session reason. Reposting location is
  // not sufficient to make the whole eligibility set true.
  if (persistentReasons.isNotEmpty || hasUnknownReason) {
    final reasons = suppliedReasons.toList()..sort();
    return ProviderLocationRejection(
      kind: ProviderLocationRejectionKind.eligibility,
      reasonCodes: List<String>.unmodifiable(reasons),
      hasUnrecognizedReason: hasUnknownReason,
    );
  }
  if (sessionReasons.isNotEmpty) {
    final reasons = suppliedReasons.toList()..sort();
    return ProviderLocationRejection(
      kind: ProviderLocationRejectionKind.locationSession,
      reasonCodes: List<String>.unmodifiable(reasons),
    );
  }

  // Every supplied reason is repairable by a later GPS observation.
  return null;
}

/// Startup notification registration may race the first location heartbeat.
/// Only this exact single-reason response receives a short grace period; mixed
/// reason sets continue through the normal stricter classifier.
bool isProviderCapabilityRegistrationRace(ApiException error) {
  if (error.errorCode != 'PROVIDER_NOT_ELIGIBLE') return false;
  final rawReasons = error.details?['reasonCodes'];
  if (rawReasons is! List || rawReasons.length != 1) return false;
  return rawReasons.single is String &&
      (rawReasons.single as String).trim().toUpperCase() ==
          'OFFER_RECEIPT_CAPABILITY_REQUIRED';
}

class ProviderLocationRetryPolicy {
  const ProviderLocationRetryPolicy({
    this.initialDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 1),
  });

  final Duration initialDelay;
  final Duration maxDelay;

  Duration delayForFailure(int consecutiveFailures) {
    if (consecutiveFailures <= 0 || initialDelay <= Duration.zero) {
      return Duration.zero;
    }
    final exponent = (consecutiveFailures - 1).clamp(0, 30);
    final multiplier = 1 << exponent;
    final candidateMicros = initialDelay.inMicroseconds * multiplier;
    return Duration(
      microseconds: candidateMicros.clamp(0, maxDelay.inMicroseconds).toInt(),
    );
  }
}

class ProviderLocationRetryGate {
  ProviderLocationRetryGate(this.policy);

  final ProviderLocationRetryPolicy policy;
  int _consecutiveFailures = 0;
  DateTime? _retryAt;

  int get consecutiveFailures => _consecutiveFailures;
  DateTime? get retryAt => _retryAt;

  bool canAttempt(DateTime now) => _retryAt == null || !now.isBefore(_retryAt!);

  void recordFailure(DateTime now) {
    _consecutiveFailures += 1;
    _retryAt = now.add(policy.delayForFailure(_consecutiveFailures));
  }

  void reset() {
    _consecutiveFailures = 0;
    _retryAt = null;
  }
}

final providerLocationRetryPolicyProvider =
    Provider<ProviderLocationRetryPolicy>(
  (_) => const ProviderLocationRetryPolicy(),
);

final providerLocationSyncNowProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);
