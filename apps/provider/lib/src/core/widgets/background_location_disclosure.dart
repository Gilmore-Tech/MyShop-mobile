import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Shows the prominent disclosure required before asking a provider for
/// background location access.
///
/// The operating system owns the actual permission decision. In particular,
/// Android 11+ requires the provider to choose "Allow all the time" from the
/// app's Settings page; the app cannot enable that choice on their behalf.
Future<bool> confirmBackgroundLocationDisclosure(
  BuildContext context,
) async {
  try {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always) return true;
  } catch (error) {
    // Still show the disclosure. The controller will perform the authoritative
    // native permission check and surface a retryable error if the plugin is
    // unavailable; a platform failure must not bypass disclosure.
    debugLog(() => '[LocationDisclosure] permission check failed: $error');
  }
  if (!context.mounted) return false;

  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Allow background location'),
          content: const Text(
            'MyShop collects your precise location while you are online, '
            'including when the app is closed or not in use. This lets us '
            'match and send you nearby ride or job requests and support '
            'active work. Location tracking stops when you go offline.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      ) ??
      false;
}

/// If location access is still unusable after the OS permission request,
/// explains the exact recovery path and offers the appropriate Settings page.
/// Returns whether a recovery dialog was shown.
Future<bool> showLocationRecoveryIfNeeded(BuildContext context) async {
  late final bool serviceEnabled;
  late final LocationPermission permission;
  try {
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    permission = await Geolocator.checkPermission();
  } catch (error) {
    debugLog(() => '[LocationDisclosure] recovery check failed: $error');
    return false;
  }

  if (serviceEnabled && permission == LocationPermission.always) return false;
  if (!context.mounted) return false;

  final needsService = !serviceEnabled;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(
        needsService
            ? 'Turn on Location Services'
            : 'Background location is off',
      ),
      content: Text(
        needsService
            ? 'Location Services must be on before you can go online.'
            : 'To stay online and receive requests when the app is in the '
                'background, set Location to Always / Allow all the time in '
                'MyShop Settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            try {
              if (needsService) {
                await Geolocator.openLocationSettings();
              } else {
                await Geolocator.openAppSettings();
              }
            } catch (error) {
              debugLog(
                  () => '[LocationDisclosure] opening Settings failed: $error');
            }
          },
          child: const Text('Open Settings'),
        ),
      ],
    ),
  );
  return true;
}
