import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'directions_service.dart';

/// Live navigation progress derived from the driver's GPS against a
/// [DirectionsRoute]. Drives the Google-Maps-style maneuver banner:
/// current step, distance to the next maneuver, and a one-line preview
/// of the step after that.
///
/// All values are computed off a single GPS fix — there's no smoothing
/// here because the location stream already filters by 5m of movement.
@immutable
class NavProgress {
  const NavProgress({
    required this.currentStepIndex,
    required this.distanceToManeuverMeters,
    this.currentStep,
    this.upcomingStep,
    this.offRouteMeters,
  });

  /// Index into [DirectionsRoute.steps]. -1 when the route has no steps
  /// (e.g. fallback straight-line route).
  final int currentStepIndex;

  /// Meters along the road until the next maneuver. Approximated by the
  /// straight-line distance from the driver to the step's
  /// `end_location` — close enough for a banner reading at city speeds.
  final double distanceToManeuverMeters;

  /// The active step. Null when there are no steps to follow.
  final DirectionsStep? currentStep;

  /// One-line preview of the maneuver after [currentStep]. Used for the
  /// secondary "Then …" hint Google Maps shows when two turns are
  /// close together.
  final DirectionsStep? upcomingStep;

  /// Distance from the driver to the nearest point on the route, in
  /// meters. Null when there's no route to compare against. The caller
  /// flags an off-route state when this exceeds a threshold (~60m on
  /// city streets — the Directions API snapped polyline is generous
  /// enough that closer than that almost always means we're still on
  /// the right road).
  final double? offRouteMeters;
}

/// Pure-function helper that turns (driver location, route) into a
/// [NavProgress]. Kept off the widget tree so the active-ride and
/// active-job screens can both consume it without duplicating math.
class NavGuidance {
  NavGuidance._();

  /// Compute the navigation progress for [driver] against [route].
  ///
  /// Algorithm: pick the step whose `end_location` we haven't yet
  /// reached, going in order. "Reached" = within 25m of `end_location`
  /// OR the driver is closer to the next step's `start_location` than
  /// the current one's `end_location`. This is the same heuristic
  /// Google Maps uses for "step complete" — robust to GPS drift in the
  /// last few meters of a turn.
  static NavProgress? progressFor({
    required LatLng? driver,
    required DirectionsRoute route,
  }) {
    if (driver == null) return null;
    if (route.steps.isEmpty) {
      return NavProgress(
        currentStepIndex: -1,
        distanceToManeuverMeters: 0,
        offRouteMeters: null,
      );
    }

    // Walk forward until we find a step whose end is still ahead.
    var idx = 0;
    for (; idx < route.steps.length; idx++) {
      final step = route.steps[idx];
      final distToEnd = _haversineMeters(driver, step.endLocation);
      if (distToEnd > 25) break;
      // If we're closer to the NEXT step's start than this step's end,
      // we've already entered the next segment — advance.
      if (idx + 1 < route.steps.length) {
        final nextStart = route.steps[idx + 1].startLocation;
        if (_haversineMeters(driver, nextStart) < distToEnd) continue;
      }
      break;
    }
    if (idx >= route.steps.length) {
      // Past the last step — arriving / arrived.
      final last = route.steps.last;
      return NavProgress(
        currentStepIndex: route.steps.length - 1,
        currentStep: last,
        distanceToManeuverMeters: _haversineMeters(driver, last.endLocation),
        offRouteMeters: _offRouteDistance(driver, route.polyline),
      );
    }

    final current = route.steps[idx];
    final upcoming =
        idx + 1 < route.steps.length ? route.steps[idx + 1] : null;
    final distToManeuver = _haversineMeters(driver, current.endLocation);
    return NavProgress(
      currentStepIndex: idx,
      currentStep: current,
      upcomingStep: upcoming,
      distanceToManeuverMeters: distToManeuver,
      offRouteMeters: _offRouteDistance(driver, route.polyline),
    );
  }

  /// Shortest distance from the driver to any segment of the route
  /// polyline, in meters. Used for off-route detection — when the
  /// returned value exceeds ~60m the caller should re-fetch directions
  /// to recompute from the driver's current position.
  static double? _offRouteDistance(LatLng driver, List<LatLng> polyline) {
    if (polyline.length < 2) return null;
    var minMeters = double.infinity;
    for (var i = 0; i < polyline.length - 1; i++) {
      final d = _pointToSegmentMeters(driver, polyline[i], polyline[i + 1]);
      if (d < minMeters) minMeters = d;
    }
    return minMeters.isFinite ? minMeters : null;
  }

  static double _pointToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    // Project to a local tangent plane around `a` (lat/lng degrees →
    // meters via a flat-earth approximation). Good enough for the
    // ≤1km segments the Directions API emits at city scale.
    const metersPerDegLat = 111320.0;
    final cosLat = math.cos(_toRadians(a.latitude));
    final metersPerDegLng = 111320.0 * cosLat;
    final ax = 0.0;
    final ay = 0.0;
    final bx = (b.longitude - a.longitude) * metersPerDegLng;
    final by = (b.latitude - a.latitude) * metersPerDegLat;
    final px = (p.longitude - a.longitude) * metersPerDegLng;
    final py = (p.latitude - a.latitude) * metersPerDegLat;
    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    if (lenSq == 0) {
      return math.sqrt(px * px + py * py);
    }
    var t = ((px - ax) * dx + (py - ay) * dy) / lenSq;
    t = t.clamp(0.0, 1.0);
    final qx = ax + t * dx;
    final qy = ay + t * dy;
    final ex = px - qx;
    final ey = py - qy;
    return math.sqrt(ex * ex + ey * ey);
  }

  static double _haversineMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLng = _toRadians(b.longitude - a.longitude);
    final lat1 = _toRadians(a.latitude);
    final lat2 = _toRadians(b.latitude);
    final s1 = math.sin(dLat / 2);
    final s2 = math.sin(dLng / 2);
    final h = s1 * s1 + s2 * s2 * math.cos(lat1) * math.cos(lat2);
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  static double _toRadians(double deg) => deg * math.pi / 180.0;
}

/// Speaks each maneuver twice — once at ~250m so the driver can plan
/// the lane change, and once at ~30m as a final confirmation. Uses
/// [FlutterTts] under the hood. No-ops if the platform plugin fails to
/// initialize (TTS engines vary across Android OEMs and iOS versions);
/// the visual banner is the source of truth, voice is gravy.
class NavVoiceCoach {
  NavVoiceCoach() {
    _init();
  }

  late final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  /// Track the (stepIndex, distanceBucket) pairs we've already announced
  /// so a slow driver doesn't get the same "in 200m turn left" four
  /// times. Distance buckets: 'far' (≥120m), 'near' (≤60m).
  final Set<String> _spoken = <String>{};

  /// Disabled flag — the screen flips this when the user mutes voice
  /// or when we know we're not actively navigating (e.g. between
  /// ride phases). All `announce()` calls become no-ops.
  bool muted = false;

  Future<void> _init() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _ready = true;
    } catch (e) {
      developer.log(
        'TTS init failed — voice coach disabled: $e',
        name: 'NavVoiceCoach',
        level: 700,
      );
    }
  }

  /// Speak the upcoming maneuver if we haven't spoken it yet at this
  /// bucket and we're inside the prompt window. Safe to call on every
  /// GPS tick — internal de-dupe handles the rate.
  Future<void> announce(NavProgress progress) async {
    if (muted || !_ready) return;
    final step = progress.currentStep;
    if (step == null) return;
    final phrase = _phraseFor(step, progress.distanceToManeuverMeters);
    if (phrase == null) return;
    final bucket = progress.distanceToManeuverMeters <= 60 ? 'near' : 'far';
    final key = '${progress.currentStepIndex}-$bucket';
    if (!_spoken.add(key)) return;
    try {
      await _tts.stop();
      await _tts.speak(phrase);
    } catch (e) {
      developer.log('TTS speak failed: $e',
          name: 'NavVoiceCoach', level: 700);
    }
  }

  /// Reset announcement memory — call when the route changes (off-route
  /// recompute, new ride leg) so the new first step gets spoken.
  void reset() => _spoken.clear();

  /// Speak a free-form phrase (e.g. "Arriving at pickup"). Not
  /// de-duplicated.
  Future<void> speak(String phrase) async {
    if (muted || !_ready) return;
    try {
      await _tts.stop();
      await _tts.speak(phrase);
    } catch (_) {/* best-effort */}
  }

  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {/* best-effort */}
  }

  /// Returns the phrase to speak, or null when we're outside the
  /// prompt windows. Windows:
  ///   - 120m..350m  → "In `<dist>`, `<instruction>`"
  ///   - dist ≤ 60m  → bare instruction ("Turn left onto X")
  static String? _phraseFor(DirectionsStep step, double distanceMeters) {
    if (step.instruction.isEmpty) return null;
    if (distanceMeters <= 60) {
      return step.instruction;
    }
    if (distanceMeters >= 120 && distanceMeters <= 350) {
      final dist = _spokenDistance(distanceMeters);
      return 'In $dist, ${step.instruction}';
    }
    return null;
  }

  static String _spokenDistance(double meters) {
    if (meters < 1000) {
      // Round to nearest 50m to keep the phrase natural.
      final rounded = (meters / 50).round() * 50;
      return '$rounded meters';
    }
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)} kilometers';
  }
}
