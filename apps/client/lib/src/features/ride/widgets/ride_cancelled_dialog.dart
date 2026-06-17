import 'package:flutter/material.dart';

/// Blocking dialog shown to the rider when the driver (or support) cancels a
/// ride they're tracking. A single OK action runs [onConfirm] — the caller
/// routes the rider back to the home screen. Barrier-dismiss is disabled so the
/// rider must acknowledge the cancellation.
Future<void> showRideCancelledDialog(
  BuildContext context,
  String message, {
  required VoidCallback onConfirm,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => AlertDialog(
      title: const Text('Ride cancelled'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(dialogCtx).pop();
            onConfirm();
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
