import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/ride_provider.dart';

class VehicleDetailsCard extends StatelessWidget {
  final MatchedDriver driver;

  const VehicleDetailsCard({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.031),
        border: Border.all(color: MyShopColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(w * 0.036, w * 0.036, w * 0.036, w * 0.026),
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'VEHICLE',
          style: TextStyle(
            fontSize: w * 0.026,
            fontWeight: FontWeight.w900,
            color: MyShopColors.textSecondary,
            letterSpacing: 1.4,
          ),
        ),
        SizedBox(height: h * 0.005),
        Text(
          driver.vehicle,
          style: TextStyle(
            fontSize: w * 0.038,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        SizedBox(height: h * 0.012),
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.026, vertical: h * 0.006),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGold,
        borderRadius: BorderRadius.circular(w * 0.015),
      ),
      child: Text(
        plate,
        style: TextStyle(
          fontSize: w * 0.031,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time_rounded, size: w * 0.033, color: MyShopColors.primaryGold),
            SizedBox(width: w * 0.010),
            Text(
              '$minutesAway mins away',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w700,
                color: MyShopColors.primaryGold,
              ),
            ),
          ],
        ),
        SizedBox(height: h * 0.002),
        Text(
          'Est. Arrival',
          style: TextStyle(
            fontSize: w * 0.026,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textSecondary,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Stack(
      children: [
        Container(
          height: h * 0.166,
          width: double.infinity,
          color: const Color(0xFFEAECEE),
          child: Center(
            child: Icon(
              Icons.directions_car_rounded,
              size: w * 0.185,
              color: MyShopColors.darkSlate,
            ),
          ),
        ),
        if (tier.isNotEmpty)
          Positioned(
            bottom: h * 0.012,
            right: w * 0.026,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.026,
                vertical:   h * 0.005,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(w * 0.010),
              ),
              child: Text(
                tier,
                style: TextStyle(
                  fontSize: w * 0.028,
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
