import 'package:flutter/material.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _darkSlate = Color(0xFF46535D);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);

enum ServiceCardType { ride, artisan }

class ServiceCard extends StatelessWidget {
  final ServiceCardType type;
  final VoidCallback? onTap;

  const ServiceCard({
    super.key,
    required this.type,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * 0.031),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: EdgeInsets.all(w * 0.041),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ServiceIcon(type: type),
            SizedBox(height: h * 0.014),
            Text(
              type == ServiceCardType.ride ? 'Book Ride' : 'Artisan',
              style: TextStyle(
                fontSize: w * 0.041,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            SizedBox(height: h * 0.005),
            Text(
              type == ServiceCardType.ride
                  ? 'Safe, verified drivers nearby'
                  : 'Hire pro help instantly',
              style: TextStyle(
                fontSize: w * 0.028,
                fontWeight: FontWeight.w400,
                color: _textSecondary,
              ),
            ),
            SizedBox(height: h * 0.012),
            Row(
              children: [
                Text(
                  'Get started',
                  style: TextStyle(
                    fontSize: w * 0.031,
                    fontWeight: FontWeight.w600,
                    color: _gold,
                  ),
                ),
                SizedBox(width: w * 0.005),
                Icon(Icons.arrow_forward, size: w * 0.031, color: _gold),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceIcon extends StatelessWidget {
  final ServiceCardType type;

  const _ServiceIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isRide = type == ServiceCardType.ride;
    return Container(
      width: w * 0.123,
      height: w * 0.123,
      decoration: BoxDecoration(
        color: isRide ? _darkSlate : _gold,
        borderRadius: BorderRadius.circular(w * 0.026),
      ),
      child: Icon(
        isRide ? Icons.directions_car_rounded : Icons.build_rounded,
        color: Colors.white,
        size: w * 0.067,
      ),
    );
  }
}
