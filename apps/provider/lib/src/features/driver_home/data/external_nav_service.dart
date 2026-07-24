import 'package:api_client/mobile_diagnostics.dart' show debugLog;
import 'dart:io' show Platform;

import 'package:url_launcher/url_launcher.dart';

/// Launches Google Maps turn-by-turn navigation to a destination.
///
/// Strategy, in order:
///   1. Android — try `google.navigation:` so the maps app opens directly
///      in driving navigation mode (skips the "preview" screen).
///   2. iOS — try `comgooglemaps://` if Google Maps is installed.
///   3. Universal fallback — `https://www.google.com/maps/dir/?api=1` which
///      opens the Google Maps app if installed or the web view otherwise.
///
/// The driver app never blocks on the result — if the launch fails (no
/// browser, no maps app, permissions revoked), we silently fall through.
/// The in-app map keeps showing the route, so the driver isn't stranded.
class ExternalNavService {
  const ExternalNavService();

  Future<bool> openDrivingNav({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final candidates = _candidateUris(lat: lat, lng: lng, label: label);
    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          final ok = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (ok) return true;
        }
      } catch (e) {
        debugLog(() => '[ExternalNav] launch failed for $uri: $e');
      }
    }
    return false;
  }

  List<Uri> _candidateUris({
    required double lat,
    required double lng,
    String? label,
  }) {
    final List<Uri> uris = [];

    if (Platform.isAndroid) {
      // `google.navigation:` launches Google Maps directly in driving
      // navigation mode — the same as tapping "Start" on a saved route.
      uris.add(Uri.parse('google.navigation:q=$lat,$lng&mode=d'));
    } else if (Platform.isIOS) {
      // comgooglemaps:// — only resolves if Google Maps is installed.
      uris.add(
        Uri.parse(
          'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
        ),
      );
    }

    // Universal fallback — opens Google Maps app if installed; otherwise
    // the browser's maps page. Works on every platform we ship to.
    uris.add(
      Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': '$lat,$lng',
        'travelmode': 'driving',
        if (label != null && label.isNotEmpty) 'destination_place_id': label,
      }),
    );

    return uris;
  }
}

const externalNavService = ExternalNavService();
