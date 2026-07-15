import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:incoming_request_overlay/incoming_request_overlay.dart';

import 'local_notification_service.dart';
import 'incoming_request_action_bridge.dart';
import 'live_activity_service.dart';

@visibleForTesting
String? safeIncomingRequestPreviewUrl(Object? value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  return uri.toString();
}

/// Stops every Android/Flutter alert surface for one incoming request.
///
/// Safe on every platform: the native overlay call is an Android no-op while
/// the ringtone and deterministic fallback notification are shared paths.
Future<void> clearIncomingRequestAlert({
  required String type,
  required String requestId,
  String? offerId,
  String reason = 'resolved',
}) async {
  final notificationIdentity = <String, dynamic>{
    'requestType': type,
    if (type == NotificationPayload.typeRideRequest)
      NotificationPayload.keyRideId: requestId
    else if (type == NotificationPayload.typeJobRequest)
      NotificationPayload.keyJobId: requestId,
    if (offerId != null && offerId.isNotEmpty)
      NotificationPayload.keyOfferId: offerId,
  };
  await Future.wait<void>([
    LocalNotificationService.instance.stopIncomingRingtone(),
    LocalNotificationService.instance.cancelIncomingRequest(
      type: type,
      requestId: requestId,
    ),
    IncomingRequestOverlayPresenter.instance.dismissByNotificationType(
      type: type,
      requestId: requestId,
      offerId: offerId,
    ),
    LiveActivityService.instance.endRequest(
      requestId: requestId,
      offerId: offerId,
      requestType: type,
      reason: reason,
    ),
    IncomingRequestActionBridge.removeDeliveredNotification(
      notificationIdentity,
    ),
  ]);
}

/// Converts the versioned backend offer contract (and the previous ride/job
/// payloads during rollout) into the platform-neutral native Android card.
class IncomingRequestOverlayPresenter {
  IncomingRequestOverlayPresenter._();

  static final IncomingRequestOverlayPresenter instance =
      IncomingRequestOverlayPresenter._();

  final IncomingRequestOverlay _overlay = IncomingRequestOverlay.instance;

  Future<bool> showFromPush(
    Map<String, dynamic> data, {
    String? notificationTitle,
  }) async {
    if (!Platform.isAndroid) return false;
    final offer = _parseOffer(data, notificationTitle: notificationTitle);
    if (offer == null) return false;
    try {
      return await _overlay.showOffer(offer);
    } catch (error) {
      debugPrint('[RequestOverlay] show failed: $error');
      return false;
    }
  }

  Future<void> dismissFromPush(Map<String, dynamic> data) async {
    if (!Platform.isAndroid) return;
    final type = _offerType(data);
    final requestId = _requestId(data, type);
    if (type == null || requestId == null || requestId.isEmpty) return;
    final offerId = _string(data['offerId']) ?? requestId;
    await dismissRequest(
      type: type,
      requestId: requestId,
      offerId: offerId,
    );
  }

  /// Removes the native card for a request that completed inside the app.
  ///
  /// Socket, REST and notification actions do not always retain the original
  /// push map, so this id-based entry point keeps terminal cleanup reliable.
  Future<void> dismissRequest({
    required IncomingRequestOfferType type,
    required String requestId,
    String? offerId,
  }) async {
    if (!Platform.isAndroid || requestId.isEmpty) return;
    try {
      await _overlay.dismissOffer(
        type: type,
        offerId: _nonEmpty(offerId) ?? requestId,
      );
    } catch (error) {
      debugPrint('[RequestOverlay] dismiss failed: $error');
    }
  }

  Future<void> dismissByNotificationType({
    required String type,
    required String requestId,
    String? offerId,
  }) async {
    final offerType = switch (NotificationPayload.normaliseType(type)) {
      NotificationPayload.typeRideRequest => IncomingRequestOfferType.ride,
      NotificationPayload.typeJobRequest => IncomingRequestOfferType.job,
      _ => null,
    };
    if (offerType == null) return;
    await dismissRequest(
      type: offerType,
      requestId: requestId,
      offerId: offerId,
    );
  }

  IncomingRequestOffer? _parseOffer(
    Map<String, dynamic> data, {
    String? notificationTitle,
  }) {
    final type = _offerType(data);
    final requestId = _requestId(data, type);
    final expiresAt = _deadline(data);
    if (type == null ||
        requestId == null ||
        requestId.isEmpty ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now().toUtc())) {
      return null;
    }

    final details = <String, dynamic>{
      ..._decodeMap(data['offerPayload']),
      ..._decodeMap(data['ridePayload']),
      ..._decodeMap(data['jobPayload']),
    };
    final offerId = _string(data['offerId']) ?? requestId;
    final routePayload = <String, String>{
      NotificationPayload.keyType: type == IncomingRequestOfferType.ride
          ? NotificationPayload.typeRideRequest
          : NotificationPayload.typeJobRequest,
      if (type == IncomingRequestOfferType.ride)
        NotificationPayload.keyRideId: requestId
      else
        NotificationPayload.keyJobId: requestId,
      NotificationPayload.keyOfferId: offerId,
      NotificationPayload.keyExpiresAt: expiresAt.toIso8601String(),
    };

    for (final key in const <String>[
      'acceptanceExpiresAt',
      'acceptanceWindowSeconds',
      'notificationId',
      'offerVersion',
    ]) {
      final value = _string(data[key]);
      if (value != null) routePayload[key] = value;
    }

    if (type == IncomingRequestOfferType.ride) {
      final farePesewas = _integer(
        details['estimatedFarePesewas'] ?? data['estimatedFarePesewas'],
      );
      final distanceKm = _number(details['distanceKm'] ?? data['distanceKm']);
      final durationMins = _number(
        details['durationMins'] ?? data['durationMins'],
      );
      return IncomingRequestOffer(
        offerId: offerId,
        type: type,
        expiresAt: expiresAt,
        title: _nonEmpty(notificationTitle) ?? 'New ride request',
        customerName: _string(details['clientName']),
        amount: farePesewas == null ? null : _formatPesewas(farePesewas),
        distance:
            distanceKm == null ? null : '${distanceKm.toStringAsFixed(1)} km',
        duration: durationMins == null
            ? null
            : '${durationMins.round().clamp(1, 999)} min',
        pickup: _string(details['pickupAddress'] ?? data['pickupAddress']),
        destination:
            _string(details['dropoffAddress'] ?? data['dropoffAddress']),
        mapPreviewUrl: safeIncomingRequestPreviewUrl(
          details['mapPreviewUrl'] ?? data['mapPreviewUrl'],
        ),
        payload: routePayload,
      );
    }

    final distanceMeters = _number(
      details['distanceMeters'] ?? data['distanceMeters'],
    );
    final distanceKm = _number(details['distanceKm'] ?? data['distanceKm']) ??
        (distanceMeters == null ? null : distanceMeters / 1000);
    final minimumBidPesewas = _integer(
      details['minBidPesewas'] ??
          details['minimumBidPesewas'] ??
          data['minBidPesewas'] ??
          data['minimumBidPesewas'],
    );
    return IncomingRequestOffer(
      offerId: offerId,
      type: type,
      expiresAt: expiresAt,
      title: _nonEmpty(notificationTitle) ?? 'New job request',
      amount: minimumBidPesewas == null
          ? 'Submit your quote'
          : 'Minimum ${_formatPesewas(minimumBidPesewas)}',
      distance:
          distanceKm == null ? null : '${distanceKm.toStringAsFixed(1)} km',
      category: _string(details['categoryName'] ?? data['categoryName']),
      location: _string(details['addressText'] ?? data['addressText']),
      description: _string(details['description']),
      photoUrl: _firstPhoto(details),
      mapPreviewUrl: safeIncomingRequestPreviewUrl(
        details['mapPreviewUrl'] ?? data['mapPreviewUrl'],
      ),
      customerName: _string(details['clientName']),
      payload: routePayload,
    );
  }

  IncomingRequestOfferType? _offerType(Map<String, dynamic> data) {
    final raw = NotificationPayload.normaliseType(
      _string(data[NotificationPayload.keyType]) ??
          _string(data['offerType']) ??
          '',
    );
    if (raw == NotificationPayload.typeRideRequest || raw == 'ride') {
      return IncomingRequestOfferType.ride;
    }
    if (raw == NotificationPayload.typeJobRequest || raw == 'job') {
      return IncomingRequestOfferType.job;
    }
    if (_string(data[NotificationPayload.keyRideId]) != null) {
      return IncomingRequestOfferType.ride;
    }
    if (_string(data[NotificationPayload.keyJobId]) != null) {
      return IncomingRequestOfferType.job;
    }
    return null;
  }

  String? _requestId(
    Map<String, dynamic> data,
    IncomingRequestOfferType? type,
  ) {
    return switch (type) {
      IncomingRequestOfferType.ride =>
        _string(data[NotificationPayload.keyRideId] ?? data['ride_id']),
      IncomingRequestOfferType.job =>
        _string(data[NotificationPayload.keyJobId] ?? data['job_id']),
      null => null,
    };
  }

  DateTime? _deadline(Map<String, dynamic> data) {
    for (final key in const <String>[
      'expiresAt',
      'expires_at',
      'acceptanceExpiresAt',
      'acceptance_expires_at',
      'requestExpiresAt',
      'request_expires_at',
    ]) {
      final raw = _string(data[key]);
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
    }
    return null;
  }

  Map<String, dynamic> _decodeMap(Object? raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is! String || raw.isEmpty) return const <String, dynamic>{};
    try {
      final decoded = json.decode(raw);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : const <String, dynamic>{};
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  String? _firstPhoto(Map<String, dynamic> details) {
    final explicit = _string(details['firstPhotoUrl'] ?? details['photoUrl']);
    if (explicit != null) return explicit;
    final photos = details['photos'];
    if (photos is List && photos.isNotEmpty) return _string(photos.first);
    return null;
  }

  String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _nonEmpty(String? value) => _string(value);

  num? _number(Object? value) => switch (value) {
        final num value => value,
        final Object value => num.tryParse(value.toString()),
        null => null,
      };

  int? _integer(Object? value) => _number(value)?.round();

  String _formatPesewas(int pesewas) {
    return 'GHS ${(pesewas / 100).toStringAsFixed(2)}';
  }
}
