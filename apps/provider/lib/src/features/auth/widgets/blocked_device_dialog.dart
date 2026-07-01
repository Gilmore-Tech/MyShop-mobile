import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_controller.dart';

/// Shows the "already signed in elsewhere" dialog and wires its three actions
/// (take over via OTP, contact support, cancel) to the [AuthController].
///
/// Shared by the screens where an [AuthBlockedByOtherDevice] state can surface
/// — including the OTP screen, since the post-OTP provider login resolves the
/// single-device conflict only after the code is verified. Returns when the
/// dialog is dismissed.
Future<void> showBlockedByOtherDeviceDialog(
  BuildContext context,
  WidgetRef ref,
  String phone,
) {
  final controller = ref.read(authControllerProvider.notifier);
  final messenger = ScaffoldMessenger.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return Consumer(
        builder: (context, ref, _) {
          final state = ref.watch(authControllerProvider);
          final blocked = state is AuthBlockedByOtherDevice ? state : null;
          final recoveryStatus =
              blocked?.recoveryRequestStatus ?? RecoveryRequestStatus.idle;
          final sendingRecovery =
              recoveryStatus == RecoveryRequestStatus.sending;
          final takingOver = blocked?.isTakingOver ?? false;
          final takeoverError = blocked?.takeoverError;
          final anyInFlight = sendingRecovery || takingOver;
          return AlertDialog(
            title: const Text('Already signed in elsewhere'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This account ($phone) is signed in on another device. '
                  'Choose "Sign me in here" to take over the session and sign '
                  'out the other device. '
                  "If you don't recognise the other device, tap "
                  'Contact support instead.',
                ),
                if (takeoverError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    takeoverError,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed:
                    anyInFlight ? null : () => controller.forceTakeover(),
                child: takingOver
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Sign me in here'),
              ),
              TextButton(
                onPressed: anyInFlight
                    ? null
                    : () async {
                        await controller.requestSessionRecovery();
                        if (!dialogContext.mounted) return;
                        final after = ref.read(authControllerProvider);
                        if (after is AuthBlockedByOtherDevice) {
                          if (after.recoveryRequestStatus ==
                              RecoveryRequestStatus.sent) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Support has been notified. '
                                  "We'll get back to you shortly.",
                                ),
                              ),
                            );
                          } else if (after.recoveryRequestStatus ==
                              RecoveryRequestStatus.failed) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Couldn't reach support. "
                                  'Please check your connection and try again.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: sendingRecovery
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Contact support'),
              ),
              TextButton(
                onPressed: anyInFlight
                    ? null
                    : () {
                        Navigator.of(dialogContext).pop();
                        controller.dismissBlockedLogin();
                      },
                child: const Text('Cancel'),
              ),
            ],
          );
        },
      );
    },
  );
}
