import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/ride_provider.dart';

/// Arrival headline + bordered driver identity card stacked vertically.
class DriverProfileHeader extends StatelessWidget {
  final MatchedDriver driver;

  const DriverProfileHeader({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      children: [
        _ArrivalHeadline(driverName: driver.name),
        SizedBox(height: h * 0.019),
        _DriverIdentityCard(driver: driver),
      ],
    );
  }
}

class _ArrivalHeadline extends StatelessWidget {
  final String driverName;
  const _ArrivalHeadline({required this.driverName});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${driverName.split(' ').first} is arriving!',
          style: TextStyle(
            fontSize: w * 0.056,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        SizedBox(height: h * 0.007),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
              height: 1.4,
            ),
            children: const [
              TextSpan(text: "We've found a highly-rated driver near\n"),
              TextSpan(
                text: 'Kumasi Central Market',
                style: TextStyle(
                  color: MyShopColors.primaryGold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverIdentityCard extends StatelessWidget {
  final MatchedDriver driver;
  const _DriverIdentityCard({required this.driver});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      padding: EdgeInsets.fromLTRB(
        w * 0.154,
        h * 0.028,
        w * 0.154,
        h * 0.024,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.036),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          const _DriverAvatar(),
          SizedBox(height: h * 0.014),
          Text(
            driver.name,
            style: TextStyle(
              fontSize: w * 0.046,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.007),
          _RatingRow(rating: driver.rating, tripCount: driver.tripCount),
          SizedBox(height: h * 0.017),
          _BadgeRow(
            isVerified: driver.isVerified,
            isPoliceChecked: driver.isPoliceChecked,
          ),
          SizedBox(height: h * 0.017),
          _PhoneChip(phone: driver.phone),
        ],
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: w * 0.195,
          height: w * 0.195,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MyShopColors.avatarPlaceholder,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            Icons.person_rounded,
            size: w * 0.108,
            color: MyShopColors.darkSlate,
          ),
        ),
        Positioned(
          bottom: w * 0.005,
          right: w * 0.005,
          child: Container(
            width: w * 0.036,
            height: w * 0.036,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MyShopColors.success,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingRow extends StatelessWidget {
  final double? rating;
  final int tripCount;
  const _RatingRow({required this.rating, required this.tripCount});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final hasRating = rating != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star_rounded,
          size: w * 0.038,
          color: hasRating
              ? MyShopColors.primaryGold
              : MyShopColors.textSecondary,
        ),
        SizedBox(width: w * 0.010),
        Text(
          hasRating ? rating!.toStringAsFixed(2) : 'New',
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        SizedBox(width: w * 0.015),
        Text(
          '· ${_formatCount(tripCount)} trips',
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w400,
            color: MyShopColors.textSecondary,
          ),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    final thousands = count ~/ 1000;
    final rest = (count % 1000).toString().padLeft(3, '0');
    return '$thousands,$rest';
  }
}

class _BadgeRow extends StatelessWidget {
  final bool isVerified;
  final bool isPoliceChecked;
  const _BadgeRow({required this.isVerified, required this.isPoliceChecked});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isVerified)
          const _OutlinedBadge(
            label: 'Verified',
            icon: Icons.check_circle_rounded,
            color: MyShopColors.success,
          ),
        if (isVerified && isPoliceChecked) SizedBox(width: w * 0.021),
        if (isPoliceChecked)
          const _OutlinedBadge(
            label: 'Police Checked',
            icon: Icons.shield_rounded,
            color: MyShopColors.textPrimary,
          ),
      ],
    );
  }
}

class _OutlinedBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _OutlinedBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.026,
        vertical: h * 0.006,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.051),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: w * 0.033, color: color),
          SizedBox(width: w * 0.013),
          Text(
            label,
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneChip extends StatelessWidget {
  final String phone;
  const _PhoneChip({required this.phone});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    if (phone.trim().isEmpty) return const SizedBox.shrink();

    // Numbers are no longer masked during the pilot — the chip dials the
    // driver's real number so the rider can call directly (e.g. to find
    // each other at pickup).
    return Semantics(
      button: true,
      label: 'Call driver',
      child: GestureDetector(
        onTap: () => dialPhoneNumber(context, phone),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: w * 0.036,
            vertical: h * 0.009,
          ),
          decoration: BoxDecoration(
            color: MyShopColors.success.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(w * 0.051),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.call_rounded,
                size: w * 0.038,
                color: MyShopColors.success,
              ),
              SizedBox(width: w * 0.018),
              Text(
                phone,
                style: TextStyle(
                  fontSize: w * 0.033,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.success,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
