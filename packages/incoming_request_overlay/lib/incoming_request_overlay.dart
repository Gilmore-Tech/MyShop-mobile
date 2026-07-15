import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The two offer layouts understood by the native Android card.
enum IncomingRequestOfferType {
  ride('ride'),
  job('job');

  const IncomingRequestOfferType(this.wireValue);

  final String wireValue;

  static IncomingRequestOfferType? tryParse(Object? value) {
    return switch (value?.toString()) {
      'ride' => IncomingRequestOfferType.ride,
      'job' => IncomingRequestOfferType.job,
      _ => null,
    };
  }
}

/// Actions emitted by the overlay before the host application is opened.
enum IncomingRequestActionType {
  rideAccept('ride_accept'),
  rideSkip('ride_skip'),
  rideView('ride_view'),
  jobBid('job_bid'),
  jobSkip('job_skip'),
  jobView('job_view'),
  unknown('unknown');

  const IncomingRequestActionType(this.wireValue);

  final String wireValue;

  static IncomingRequestActionType fromWire(Object? value) {
    final wire = value?.toString();
    for (final action in values) {
      if (action.wireValue == wire) return action;
    }
    return IncomingRequestActionType.unknown;
  }
}

/// Data rendered by the native Android overlay.
///
/// All fields are deliberately display-ready strings. The package has no
/// dependency on MyShop models or formatting rules, which keeps it reusable
/// from a background Flutter engine. [payload] is returned unchanged with any
/// action so the host can carry routing or idempotency metadata.
@immutable
class IncomingRequestOffer {
  IncomingRequestOffer({
    required this.offerId,
    required this.type,
    required this.expiresAt,
    required this.title,
    this.customerName,
    this.amount,
    this.distance,
    this.duration,
    this.pickup,
    this.destination,
    this.category,
    this.location,
    this.description,
    this.photoUrl,
    this.mapPreviewUrl,
    Map<String, String> payload = const <String, String>{},
  }) : payload = Map<String, String>.unmodifiable(payload) {
    if (offerId.trim().isEmpty) {
      throw ArgumentError.value(offerId, 'offerId', 'must not be empty');
    }
    if (title.trim().isEmpty) {
      throw ArgumentError.value(title, 'title', 'must not be empty');
    }
  }

  final String offerId;
  final IncomingRequestOfferType type;

  /// Absolute server-authored deadline. The native layer never extends it.
  final DateTime expiresAt;
  final String title;
  final String? customerName;
  final String? amount;
  final String? distance;
  final String? duration;
  final String? pickup;
  final String? destination;
  final String? category;
  final String? location;
  final String? description;
  final String? photoUrl;

  /// Short-lived, opaque HTTPS image URL authored by the backend.
  ///
  /// Native Android renders this only after the device is unlocked. It is a
  /// dedicated display field rather than part of [payload], so it is never
  /// persisted with durable action events.
  final String? mapPreviewUrl;
  final Map<String, String> payload;

  @visibleForTesting
  Map<String, Object> toMap() {
    return <String, Object>{
      'offerId': offerId,
      'offerType': type.wireValue,
      'expiresAtMillis': expiresAt.toUtc().millisecondsSinceEpoch,
      'title': title,
      if (_present(customerName)) 'customerName': customerName!.trim(),
      if (_present(amount)) 'amount': amount!.trim(),
      if (_present(distance)) 'distance': distance!.trim(),
      if (_present(duration)) 'duration': duration!.trim(),
      if (_present(pickup)) 'pickup': pickup!.trim(),
      if (_present(destination)) 'destination': destination!.trim(),
      if (_present(category)) 'category': category!.trim(),
      if (_present(location)) 'location': location!.trim(),
      if (_present(description)) 'description': description!.trim(),
      if (_present(photoUrl)) 'photoUrl': photoUrl!.trim(),
      if (_present(mapPreviewUrl)) 'mapPreviewUrl': mapPreviewUrl!.trim(),
      'payload': payload,
    };
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;
}

/// A durable native action drained at startup or received live over the event
/// channel. Native code writes the action to SharedPreferences before it tries
/// to launch the host app, so a killed process cannot lose the button tap.
@immutable
class IncomingRequestOverlayAction {
  IncomingRequestOverlayAction({
    required this.actionId,
    required this.action,
    required this.offerId,
    required this.offerType,
    required this.occurredAt,
    Map<String, String> payload = const <String, String>{},
  }) : payload = Map<String, String>.unmodifiable(payload);

  factory IncomingRequestOverlayAction.fromMap(Map<Object?, Object?> map) {
    final actionId = map['actionId']?.toString() ?? '';
    final action = IncomingRequestActionType.fromWire(map['action']);
    final offerId = map['offerId']?.toString() ?? '';
    final offerType = IncomingRequestOfferType.tryParse(map['offerType']);
    final occurredAtMillis = switch (map['occurredAtMillis']) {
      final int value => value,
      final num value => value.toInt(),
      final Object value => int.tryParse(value.toString()) ?? 0,
      null => 0,
    };
    final rawPayload = map['payload'];
    final payload = <String, String>{};
    if (rawPayload is Map) {
      for (final entry in rawPayload.entries) {
        if (entry.key != null && entry.value != null) {
          payload[entry.key.toString()] = entry.value.toString();
        }
      }
    }

    if (actionId.isEmpty ||
        offerId.isEmpty ||
        offerType == null ||
        occurredAtMillis <= 0) {
      throw FormatException('Malformed incoming-request overlay action: $map');
    }

    return IncomingRequestOverlayAction(
      actionId: actionId,
      action: action,
      offerId: offerId,
      offerType: offerType,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        occurredAtMillis,
        isUtc: true,
      ),
      payload: payload,
    );
  }

  /// Stable native queue id used to acknowledge successful handling.
  final String actionId;
  final IncomingRequestActionType action;
  final String offerId;
  final IncomingRequestOfferType offerType;
  final DateTime occurredAt;
  final Map<String, String> payload;
}

/// Host-facing API for the Android incoming-request overlay.
class IncomingRequestOverlay {
  IncomingRequestOverlay._({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _methodChannel = methodChannel ??
            const MethodChannel(
              'com.gilmoretech.incoming_request_overlay/methods',
            ),
        _eventChannel = eventChannel ??
            const EventChannel(
              'com.gilmoretech.incoming_request_overlay/actions',
            );

  /// Test-only constructor that permits mocked platform channels.
  @visibleForTesting
  IncomingRequestOverlay.withChannels({
    required MethodChannel methodChannel,
    required EventChannel eventChannel,
  }) : this._(methodChannel: methodChannel, eventChannel: eventChannel);

  static final IncomingRequestOverlay instance = IncomingRequestOverlay._();

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<IncomingRequestOverlayAction>? _actions;

  /// Live actions from an already-running native overlay.
  ///
  /// Always call [drainPendingActions] during authenticated app startup too;
  /// event channels cannot replay an action emitted before Flutter attached.
  Stream<IncomingRequestOverlayAction> get actions {
    return _actions ??= _eventChannel.receiveBroadcastStream().map((
      Object? event,
    ) {
      if (event is! Map) {
        throw FormatException('Overlay action is not a map: $event');
      }
      return IncomingRequestOverlayAction.fromMap(
        Map<Object?, Object?>.from(event),
      );
    }).asBroadcastStream();
  }

  Future<bool> isSupported() async {
    return await _methodChannel.invokeMethod<bool>('isSupported') ?? false;
  }

  Future<bool> canDrawOverlays() async {
    return await _methodChannel.invokeMethod<bool>('canDrawOverlays') ?? false;
  }

  /// Opens the Android per-app overlay permission screen.
  ///
  /// Returns false on unsupported platforms or if Android cannot resolve the
  /// settings intent. Grant status must be checked again after app resume.
  Future<bool> openOverlaySettings() async {
    return await _methodChannel.invokeMethod<bool>('openOverlaySettings') ??
        false;
  }

  /// Displays or replaces the native card for [offer].
  ///
  /// Returns false when permission is absent, the deadline has already passed,
  /// or Android refuses to start the short-lived service. The caller should
  /// render its normal high-priority notification fallback in that case.
  Future<bool> showOffer(IncomingRequestOffer offer) async {
    if (!offer.expiresAt.toUtc().isAfter(DateTime.now().toUtc())) return false;
    return await _methodChannel.invokeMethod<bool>(
          'showOffer',
          offer.toMap(),
        ) ??
        false;
  }

  Future<void> dismissOffer({
    required IncomingRequestOfferType type,
    required String offerId,
  }) async {
    if (offerId.trim().isEmpty) return;
    await _methodChannel.invokeMethod<void>('dismissOffer', <String, Object>{
      'offerId': offerId,
      'offerType': type.wireValue,
    });
  }

  Future<void> dismissAll() {
    return _methodChannel.invokeMethod<void>('dismissAll');
  }

  /// Returns native actions saved before Flutter attached without removing them.
  ///
  /// The historical "drain" name is retained for API compatibility, but
  /// delivery is deliberately peek-and-ack. Call [acknowledgeAction] only after
  /// the host has safely completed or durably handed off an action.
  Future<List<IncomingRequestOverlayAction>> drainPendingActions() async {
    final raw =
        await _methodChannel.invokeListMethod<Object?>('drainPendingActions') ??
            const <Object?>[];
    return raw.whereType<Map>().map((Map item) {
      return IncomingRequestOverlayAction.fromMap(
        Map<Object?, Object?>.from(item),
      );
    }).toList(growable: false);
  }

  /// Permanently removes one successfully handled native action.
  Future<void> acknowledgeAction(String actionId) async {
    final normalized = actionId.trim();
    if (normalized.isEmpty) return;
    await _methodChannel.invokeMethod<void>(
      'acknowledgeAction',
      <String, String>{'actionId': normalized},
    );
  }
}
