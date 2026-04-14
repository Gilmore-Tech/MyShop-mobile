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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ServiceIcon(type: type),
            const SizedBox(height: 12),
            Text(
              type == ServiceCardType.ride ? 'Book Ride' : 'Artisan',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              type == ServiceCardType.ride
                  ? 'Safe, verified drivers nearby'
                  : 'Hire pro help instantly',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: _textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              children: [
                Text(
                  'Get started',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _gold,
                  ),
                ),
                SizedBox(width: 2),
                Icon(Icons.arrow_forward, size: 12, color: _gold),
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
    final isRide = type == ServiceCardType.ride;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: isRide ? _darkSlate : _gold,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isRide ? Icons.directions_car_rounded : Icons.build_rounded,
        color: Colors.white,
        size: 26,
      ),
    );
  }
}
