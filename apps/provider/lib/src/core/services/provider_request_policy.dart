import 'package:api_client/api_client.dart';

const String providerRequestBlockCode = 'PROVIDER_REQUEST_BLOCK';
const String legacyProviderCancellationBlockCode =
    'PROVIDER_CANCELLATION_BLOCK';

bool isProviderRequestBlock(ApiException error) =>
    error.errorCode == providerRequestBlockCode ||
    error.errorCode == legacyProviderCancellationBlockCode;

ProviderRequestRestriction? providerRequestRestrictionFromError(
  ApiException error,
) {
  if (!isProviderRequestBlock(error)) return null;
  final details = error.details;
  if (details == null) return const ProviderRequestRestriction();
  final nested = details['activeRestriction'];
  if (nested is Map) {
    return ProviderRequestRestriction.fromJson(
      Map<String, dynamic>.from(nested),
    );
  }
  return ProviderRequestRestriction.fromJson(details);
}

/// Stable provider-facing copy for both the new response-policy block and the
/// legacy cancellation-only block. Declines/missed offers are kept explicitly
/// separate from the public customer rating.
String providerRequestBlockMessage(
  ApiException error, {
  String requestLabel = 'requests',
  DateTime? now,
}) {
  final restriction = providerRequestRestrictionFromError(error);
  final policyKind = restriction?.policyKind?.trim().toLowerCase();
  final remaining = _remainingLabel(restriction, now: now);
  final suffix = remaining == null
      ? 'You will receive new $requestLabel again automatically when the pause ends.'
      : 'You can receive new $requestLabel again $remaining.';

  if (error.errorCode == legacyProviderCancellationBlockCode ||
      policyKind == 'cancellation' ||
      policyKind == 'accepted_cancellation') {
    return 'New $requestLabel are temporarily paused after repeated accepted-work cancellations. '
        '$suffix Contact support if you need help.';
  }
  if (policyKind == 'response' ||
      policyKind == 'request_response' ||
      policyKind == 'offer_response') {
    return 'New $requestLabel are temporarily paused after repeated declines or missed requests. '
        '$suffix This does not change your customer rating.';
  }
  return 'New $requestLabel are temporarily paused. $suffix '
      'This does not change your customer rating.';
}

String providerActiveRestrictionMessage(
  ProviderRequestRestriction restriction, {
  DateTime? now,
}) {
  final synthetic = ApiException(
    message: 'Provider request pause',
    statusCode: 429,
    errorCode: providerRequestBlockCode,
    details: <String, dynamic>{
      if (restriction.policyKind != null) 'policyKind': restriction.policyKind,
      if (restriction.blockedUntil != null)
        'blockedUntil': restriction.blockedUntil!.toIso8601String(),
      if (restriction.retryAfterSeconds != null)
        'retryAfterSeconds': restriction.retryAfterSeconds,
      if (restriction.count != null) 'count': restriction.count,
      if (restriction.points != null) 'points': restriction.points,
      if (restriction.threshold != null) 'threshold': restriction.threshold,
    },
  );
  return providerRequestBlockMessage(synthetic, now: now);
}

/// Builds provider-facing performance copy only from server-authored metrics.
/// Missing/legacy fields deliberately produce neutral text instead of a
/// fabricated percentage.
String providerRequestResponseSummaryMessage(
  ProviderRequestResponseSummary? summary, {
  required bool isOnline,
  DateTime? now,
}) {
  final restriction = summary?.activeRestriction;
  if (restriction != null) {
    return providerActiveRestrictionMessage(restriction, now: now);
  }
  if (summary == null || !summary.hasSample) {
    return isOnline
        ? 'You are available for requests. Response activity will appear after you receive an eligible offer.'
        : 'Go online to receive requests. Declines and missed requests are tracked separately from customer ratings.';
  }

  String rate(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  final responseRate = summary.responseRatePercent;
  final acceptanceRate = summary.acceptanceRatePercent;
  final period =
      summary.periodDays > 0 ? ' over the last ${summary.periodDays} days' : '';
  final metrics = <String>[
    if (responseRate != null)
      'responded to ${rate(responseRate)}% of eligible requests',
    if (acceptanceRate != null)
      'accepted ${rate(acceptanceRate)}% of eligible requests',
  ];
  if (metrics.isEmpty) {
    return 'Recent request activity is available, but no response or acceptance rate was supplied. Your customer rating is separate.';
  }
  return 'You ${metrics.join(' and ')}$period. Declines and missed requests do not change your customer rating.';
}

String? _remainingLabel(
  ProviderRequestRestriction? restriction, {
  DateTime? now,
}) {
  if (restriction == null) return null;
  var seconds = restriction.retryAfterSeconds;
  final blockedUntil = restriction.blockedUntil;
  if (blockedUntil != null) {
    final delta = blockedUntil.difference((now ?? DateTime.now()).toUtc());
    if (delta > Duration.zero) {
      seconds = delta.inSeconds + (delta.inMilliseconds % 1000 == 0 ? 0 : 1);
    }
  }
  if (seconds == null || seconds <= 0) return null;
  if (seconds < 60) return 'in less than a minute';
  final minutes = (seconds / 60).ceil();
  if (minutes < 60) {
    return 'in $minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  }
  final hours = (minutes / 60).ceil();
  return 'in $hours ${hours == 1 ? 'hour' : 'hours'}';
}
