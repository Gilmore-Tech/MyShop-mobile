import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

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
              type == ServiceCardType.ride ? 'Book Akwaaba Ride' : 'MyShop Artisan',
              style: TextStyle(
                fontSize: w * 0.034,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
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
                color: MyShopColors.textSecondary,
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
                    color: MyShopColors.primaryGold,
                  ),
                ),
                SizedBox(width: w * 0.005),
                Icon(Icons.arrow_forward,
                    size: w * 0.031, color: MyShopColors.primaryGold),
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
        color: isRide ? MyShopColors.darkSlate : MyShopColors.primaryGold,
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
