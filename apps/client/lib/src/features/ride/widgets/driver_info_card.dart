import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/ride_provider.dart';
import '../screens/driver_found_screen.dart';

class DriverInfoCard extends StatelessWidget {
  final MatchedDriver driver;

  const DriverInfoCard({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DriverFoundScreen(driver: driver),
        ),
      ),
      child: _DriverCardContent(driver: driver),
    );
  }
}

class _DriverCardContent extends StatelessWidget {
  final MatchedDriver driver;
  const _DriverCardContent({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          _DriverAvatar(photoUrl: driver.photoUrl),
          const SizedBox(width: 14),
          Expanded(child: _DriverDetails(driver: driver)),
          _AcceptedBadge(),
        ],
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.photoUrl});
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MyShopColors.avatarPlaceholder,
        border: Border.all(color: MyShopColors.primaryGold, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl.isEmpty
          ? const Icon(
              Icons.person_rounded,
              size: 30,
              color: MyShopColors.darkSlate,
            )
          : CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              memCacheWidth: (size * 3).round(),
              memCacheHeight: (size * 3).round(),
              placeholder: (_, __) => const Icon(
                Icons.person_rounded,
                size: 30,
                color: MyShopColors.darkSlate,
              ),
              errorWidget: (_, __, ___) => const Icon(
                Icons.person_rounded,
                size: 30,
                color: MyShopColors.darkSlate,
              ),
            ),
    );
  }
}

class _DriverDetails extends StatelessWidget {
  final MatchedDriver driver;
  const _DriverDetails({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          driver.name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${driver.vehicle} • ${driver.plateNumber}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.star_rounded, size: 14, color: MyShopColors.primaryGold),
            const SizedBox(width: 3),
            Text(
              driver.rating.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary,
              ),
            ),
            const SizedBox(width: 10),
            const Icon(Icons.access_time_rounded,
                size: 13, color: MyShopColors.textSecondary),
            const SizedBox(width: 3),
            Text(
              '${driver.minutesAway} mins away',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AcceptedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Accepted',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: MyShopColors.success,
        ),
      ),
    );
  }
}
