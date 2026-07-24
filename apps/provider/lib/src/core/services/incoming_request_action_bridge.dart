import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:incoming_request_overlay/incoming_request_overlay.dart';

import 'local_notification_service.dart';

/// Replays durable iOS request actions into the same Dart handler used by
/// Android/local-notification taps.
///
/// The native AppDelegate stores every action before completing the iOS
/// callback. We acknowledge only after the asynchronous REST/routing handler
/// finishes, so a process death during handling replays the action next launch.
class IncomingRequestActionBridge {
  IncomingRequestActionBridge({
    required Future<void> Function(Map<String, dynamic>) handleAction,
  }) : _handleAction = handleAction;

  static const MethodChannel _iosMethods = MethodChannel(
    'com.gilmoretech.myshop/request_action',
  );
  static const EventChannel _iosEvents = EventChannel(
    'com.gilmoretech.myshop/request_action/events',
  );

  final Future<void> Function(Map<String, dynamic>) _handleAction;
  final Set<String> _processingIds = <String>{};
  final IncomingRequestOverlay _androidOverlay =
      IncomingRequestOverlay.instance;
  StreamSubscription<IncomingRequestOverlayAction>? _androidSubscription;
  StreamSubscription<Object?>? _iosSubscription;

  static Future<void> removeDeliveredNotification(
    Map<String, dynamic> payload,
  ) async {
    if (!Platform.isIOS) return;
    try {
      await _iosMethods.invokeMethod<void>(
        'removeDeliveredRequestNotification',
        payload,
      );
    } on MissingPluginException {
      // Expected on non-iOS test hosts/background engines that are closing.
    } catch (error) {
      debugLog(() => '[RequestAction] iOS notification removal failed: $error');
    }
  }

  Future<void> start() async {
    if (Platform.isAndroid) {
      await _startAndroid();
      return;
    }
    if (!Platform.isIOS) return;
    _iosSubscription ??= _iosEvents.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          unawaited(_processIosAction(Map<String, dynamic>.from(event)));
        }
      },
      onError: (Object error) {
        debugLog(() => '[RequestAction] iOS event stream failed: $error');
      },
    );

    try {
      final pending = await _iosMethods.invokeListMethod<Object?>(
            'getPendingRequestActions',
          ) ??
          const <Object?>[];
      for (final item in pending) {
        if (item is Map) {
          await _processIosAction(Map<String, dynamic>.from(item));
        }
      }
    } on MissingPluginException {
      // Expected on non-iOS test hosts.
    } catch (error) {
      debugLog(() => '[RequestAction] iOS pending replay failed: $error');
    }
  }

  Future<void> _startAndroid() async {
    _androidSubscription ??= _androidOverlay.actions.listen(
      (action) => unawaited(_processAndroidAction(action)),
      onError: (Object error) {
        debugLog(() => '[RequestAction] Android event stream failed: $error');
      },
    );

    try {
      // This is a non-destructive peek. Native storage removes an action only
      // after [acknowledgeAction] below, so a process death cannot lose it.
      final pending = await _androidOverlay.drainPendingActions();
      for (final action in pending) {
        await _processAndroidAction(action);
      }
    } on MissingPluginException {
      // Expected on non-Android test hosts/background engines that are closing.
    } catch (error) {
      debugLog(() => '[RequestAction] Android pending replay failed: $error');
    }
  }

  Future<void> _processAndroidAction(
    IncomingRequestOverlayAction event,
  ) async {
    if (!_processingIds.add(event.actionId)) return;
    final selectedAction = switch (event.action) {
      IncomingRequestActionType.rideAccept =>
        NotificationPayload.actionRideAccept,
      IncomingRequestActionType.rideSkip => NotificationPayload.actionRideSkip,
      IncomingRequestActionType.rideView => NotificationPayload.actionRideView,
      IncomingRequestActionType.jobBid =>
        NotificationPayload.actionJobSubmitBid,
      IncomingRequestActionType.jobSkip => NotificationPayload.actionJobSkip,
      IncomingRequestActionType.jobView => NotificationPayload.actionJobView,
      IncomingRequestActionType.unknown => null,
    };

    try {
      if (selectedAction == null) {
        // A future app version may add native actions this build does not know.
        // Acknowledge it rather than replaying an unhandleable action forever.
        await _androidOverlay.acknowledgeAction(event.actionId);
        return;
      }
      final type = event.offerType == IncomingRequestOfferType.ride
          ? NotificationPayload.typeRideRequest
          : NotificationPayload.typeJobRequest;
      final idKey = event.offerType == IncomingRequestOfferType.ride
          ? NotificationPayload.keyRideId
          : NotificationPayload.keyJobId;
      final payload = <String, dynamic>{
        ...event.payload,
        NotificationPayload.keyType: type,
        idKey: event.payload[idKey] ?? event.offerId,
        NotificationPayload.keyOfferId: event.offerId,
        NotificationPayload.keyActionId: selectedAction,
      };

      await _handleAction(payload);
      await _androidOverlay.acknowledgeAction(event.actionId);
    } catch (error, stackTrace) {
      debugLog(
        () => '[RequestAction] Android action $selectedAction failed: $error\n'
            '$stackTrace',
      );
      // Deliberately leave it pending for a later replay.
    } finally {
      _processingIds.remove(event.actionId);
    }
  }

  Future<void> _processIosAction(Map<String, dynamic> event) async {
    final queueId = event['actionId']?.toString();
    final selectedAction =
        (event['action'] ?? event['actionIdentifier'])?.toString();
    if (queueId == null ||
        queueId.isEmpty ||
        selectedAction == null ||
        selectedAction.isEmpty ||
        !_processingIds.add(queueId)) {
      return;
    }

    try {
      final payload = <String, dynamic>{...event};
      final requestType = event['requestType']?.toString();
      if (requestType != null && requestType.isNotEmpty) {
        payload[NotificationPayload.keyType] = requestType;
      } else if (payload[NotificationPayload.keyRideId] != null) {
        payload[NotificationPayload.keyType] =
            NotificationPayload.typeRideRequest;
      } else if (payload[NotificationPayload.keyJobId] != null) {
        payload[NotificationPayload.keyType] =
            NotificationPayload.typeJobRequest;
      }
      payload[NotificationPayload.keyActionId] = selectedAction;

      await _handleAction(payload);
      await _iosMethods.invokeMethod<void>(
        'acknowledgeRequestAction',
        <String, String>{'actionId': queueId},
      );
    } catch (error, stackTrace) {
      debugLog(
        () => '[RequestAction] iOS action $selectedAction failed: $error\n'
            '$stackTrace',
      );
      // Deliberately leave it pending for a later replay.
    } finally {
      _processingIds.remove(queueId);
    }
  }

  Future<void> dispose() async {
    await _androidSubscription?.cancel();
    _androidSubscription = null;
    await _iosSubscription?.cancel();
    _iosSubscription = null;
  }
}
