import 'dart:io' show Platform;

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/di/providers.dart';
import '../../../core/services/local_notification_service.dart';

final Set<String> _callsStarting = <String>{};

Future<void> startClientInAppCall(
  BuildContext context,
  WidgetRef ref, {
  required String bookingType,
  required String bookingId,
}) async {
  final startKey = '$bookingType:$bookingId';
  if (!_callsStarting.add(startKey)) return;
  final callService = ref.read(appCallServiceProvider);
  try {
    if (Platform.isAndroid) {
      await LocalNotificationService.instance.requestFullScreenCallPermission();
    }
    final session = await callService.startCall(
      bookingType: bookingType,
      bookingId: bookingId,
    );
    if (!context.mounted) {
      try {
        await callService.endCall(session.callId);
      } catch (error) {
        debugPrint(
          '[Call] failed to clean up detached call ${session.callId}: $error',
        );
      }
      return;
    }
    context.push(AppRoutes.inAppCallPath(session.callId), extra: session);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_callStartErrorMessage(error))),
    );
  } finally {
    _callsStarting.remove(startKey);
  }
}

String _callStartErrorMessage(Object error) {
  if (error is ApiException) {
    return userSafeApiErrorMessage(
      error,
      fallback: 'Could not start in-app call. Please try again.',
      conflictMessage:
          'This call is no longer available. Refresh the booking and try again.',
    );
  }
  return 'Could not start in-app call. Please try again.';
}
