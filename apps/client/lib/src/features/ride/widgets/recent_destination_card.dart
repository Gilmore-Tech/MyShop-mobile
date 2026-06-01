import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/ride_provider.dart';

class RecentDestinationCard extends StatelessWidget {
  final RecentDestination destination;
  final VoidCallback? onTap;

  const RecentDestinationCard({
    super.key,
    required this.destination,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            _DestinationIcon(isHome: destination.isHome),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    destination.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    destination.address,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationIcon extends StatelessWidget {
  final bool isHome;
  const _DestinationIcon({required this.isHome});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: w * 0.092,
      height: w * 0.092,
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceGrey,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isHome ? Icons.home_rounded : Icons.business_rounded,
        size: w * 0.046,
        color: MyShopColors.darkSlate,
      ),
    );
  }
}
