import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../services/nav_guidance.dart';

/// Google-Maps-style turn-by-turn banner. Big maneuver arrow on the
/// left, distance + instruction on the right, and an optional "Then …"
/// preview underneath when two maneuvers are tightly chained.
///
/// Falls back gracefully when [progress] is null or has no
/// [NavProgress.currentStep] — the widget renders the simpler
/// distance/ETA card so a driver outside Google's coverage zone (or
/// stuck on the fallback straight-line route) still gets a useful
/// header instead of a blank slot.
class ManeuverBanner extends StatelessWidget {
  const ManeuverBanner({
    super.key,
    required this.progress,
    required this.fallbackDistanceMeters,
    required this.fallbackEtaMinutes,
    required this.fallbackAddress,
    required this.phaseLabel,
  });

  /// Live navigation progress. Null while we wait for the first GPS fix
  /// or Directions response — the banner shows the fallback content
  /// (distance + ETA) until this arrives.
  final NavProgress? progress;

  /// Straight-line distance from the driver to the leg's destination,
  /// in meters. Used when [progress] has no current step.
  final double? fallbackDistanceMeters;

  /// ETA in minutes, derived from the route's average speed by the
  /// caller. Used in the right-hand column when there's no maneuver.
  final int? fallbackEtaMinutes;

  /// Pickup / drop-off address the driver is heading to.
  final String fallbackAddress;

  /// "TO PICKUP" / "TO DESTINATION" — drives the small label in the
  /// fallback view.
  final String phaseLabel;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final step = progress?.currentStep;
    return Padding(
      padding: EdgeInsets.only(
        top: topPadding + 12,
        left: MyShopSpacing.md,
        right: MyShopSpacing.md,
      ),
      child: Material(
        elevation: 6,
        shadowColor: const Color(0x33000000),
        borderRadius: BorderRadius.circular(16),
        color: MyShopColors.surfaceWhite,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MyShopSpacing.md,
            vertical: 14,
          ),
          child: step != null
              ? _ManeuverContent(progress: progress!)
              : _FallbackContent(
                  distanceMeters: fallbackDistanceMeters,
                  etaMinutes: fallbackEtaMinutes,
                  address: fallbackAddress,
                  phaseLabel: phaseLabel,
                ),
        ),
      ),
    );
  }
}

class _ManeuverContent extends StatelessWidget {
  const _ManeuverContent({required this.progress});

  final NavProgress progress;

  @override
  Widget build(BuildContext context) {
    final step = progress.currentStep!;
    final upcoming = progress.upcomingStep;
    final distance = progress.distanceToManeuverMeters;
    final distanceLabel = _formatDistance(distance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Maneuver arrow tile — dark slate so the icon reads at
            // a glance even in bright sunlight.
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: MyShopColors.darkSlate,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _maneuverIcon(step.maneuver),
                size: 30,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    distanceLabel,
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textPrimary,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    step.instruction.isNotEmpty ? step.instruction : 'Continue',
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textSecondary,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        // "Then turn right" preview — only when the upcoming step is
        // within ~300m of the current maneuver, mirroring Google Maps'
        // tight-turn hint.
        if (upcoming != null && upcoming.distanceMeters <= 300) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: MyShopColors.divider),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                _maneuverIcon(upcoming.maneuver),
                size: 18,
                color: MyShopColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Then ${upcoming.instruction}',
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    color: MyShopColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _formatDistance(double meters) {
    if (meters < 1000) {
      // Round to the nearest 10m so the label doesn't jitter on each
      // GPS fix.
      final rounded = (meters / 10).round() * 10;
      return '$rounded m';
    }
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(1)} km';
  }

  /// Maps Google's `maneuver` string to a Material icon. Returns a
  /// straight-ahead arrow when the maneuver is unknown or empty — the
  /// most common case for "continue on the same road" segments.
  static IconData _maneuverIcon(String maneuver) {
    switch (maneuver) {
      case 'turn-left':
        return Icons.turn_left;
      case 'turn-right':
        return Icons.turn_right;
      case 'turn-sharp-left':
      case 'turn-slight-left':
        return Icons.turn_sharp_left;
      case 'turn-sharp-right':
      case 'turn-slight-right':
        return Icons.turn_sharp_right;
      case 'uturn-left':
      case 'uturn-right':
        return Icons.u_turn_left;
      case 'ramp-left':
      case 'fork-left':
        return Icons.ramp_left;
      case 'ramp-right':
      case 'fork-right':
        return Icons.ramp_right;
      case 'merge':
        return Icons.merge;
      case 'roundabout-left':
      case 'roundabout-right':
        return Icons.roundabout_right;
      case 'straight':
      case '':
      default:
        return Icons.straight;
    }
  }
}

class _FallbackContent extends StatelessWidget {
  const _FallbackContent({
    required this.distanceMeters,
    required this.etaMinutes,
    required this.address,
    required this.phaseLabel,
  });

  final double? distanceMeters;
  final int? etaMinutes;
  final String address;
  final String phaseLabel;

  @override
  Widget build(BuildContext context) {
    final distanceLabel = distanceMeters != null
        ? (distanceMeters! < 1000
            ? '${distanceMeters!.round()} m'
            : '${(distanceMeters! / 1000).toStringAsFixed(1)} km')
        : '— km';
    final etaLabel = (etaMinutes != null && etaMinutes! > 0)
        ? '${etaMinutes!} min'
        : (etaMinutes == 0 ? 'Arriving' : '—');
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.navigation,
              size: 22, color: MyShopColors.darkSlate),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(distanceLabel,
                  style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textPrimary)),
              Text(address,
                  style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 12,
                      color: MyShopColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Container(
          width: 1,
          height: 36,
          color: MyShopColors.divider,
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(phaseLabel,
                style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.primaryGold,
                    letterSpacing: 0.5)),
            const SizedBox(height: 2),
            Text(etaLabel,
                style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textPrimary)),
          ],
        ),
      ],
    );
  }
}
