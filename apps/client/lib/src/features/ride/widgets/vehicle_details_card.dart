import 'package:flutter/material.dart';
import '../providers/ride_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _border = Color(0xFFE0E0E0);
const _darkSlate = Color(0xFF46535D);

class VehicleDetailsCard extends StatelessWidget {
  final MatchedDriver driver;

  const VehicleDetailsCard({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: _VehicleInfo(driver: driver),
          ),
          _CarImage(tier: driver.vehicleTier),
        ],
      ),
    );
  }
}

class _VehicleInfo extends StatelessWidget {
  final MatchedDriver driver;
  const _VehicleInfo({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'VEHICLE',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: _textSecondary,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          driver.vehicle,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _PlateBadge(plate: driver.plateNumber),
            const Spacer(),
            _EtaInfo(minutesAway: driver.minutesAway),
          ],
        ),
      ],
    );
  }
}

class _PlateBadge extends StatelessWidget {
  final String plate;
  const _PlateBadge({required this.plate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _gold,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        plate,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _EtaInfo extends StatelessWidget {
  final int minutesAway;
  const _EtaInfo({required this.minutesAway});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.access_time_rounded, size: 13, color: _gold),
            const SizedBox(width: 4),
            Text(
              '$minutesAway mins away',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _gold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          'Est. Arrival',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}

class _CarImage extends StatelessWidget {
  final String tier;
  const _CarImage({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          height: 140,
          width: double.infinity,
          color: const Color(0xFFEAECEE),
          child: const Center(
            child: Icon(
              Icons.directions_car_rounded,
              size: 72,
              color: _darkSlate,
            ),
          ),
        ),
        if (tier.isNotEmpty)
          Positioned(
            bottom: 10,
            right: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                tier,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
