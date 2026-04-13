import 'package:flutter/material.dart';
import '../providers/ride_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _success = Color(0xFF27AE60);
const _successLight = Color(0xFFE8F8EF);
const _goldLight = Color(0xFFFFF8EC);
const _avatarBg = Color(0xFFE0E6FF);
const _darkSlate = Color(0xFF46535D);

class DriverProfileHeader extends StatelessWidget {
  final MatchedDriver driver;

  const DriverProfileHeader({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        children: [
          _ArrivalHeadline(driverName: driver.name),
          const SizedBox(height: 20),
          _DriverAvatar(),
          const SizedBox(height: 14),
          Text(
            driver.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _RatingRow(rating: driver.rating, tripCount: driver.tripCount),
          const SizedBox(height: 10),
          _BadgeRow(
            isVerified: driver.isVerified,
            isPoliceChecked: driver.isPoliceChecked,
          ),
          const SizedBox(height: 10),
          _PhoneRow(maskedPhone: driver.maskedPhone),
        ],
      ),
    );
  }
}

class _ArrivalHeadline extends StatelessWidget {
  final String driverName;
  const _ArrivalHeadline({required this.driverName});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${driverName.split(' ').first} is arriving!',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: _textSecondary,
            ),
            children: [
              const TextSpan(text: "We've found a highly-rated driver near\n"),
              TextSpan(
                text: 'Kumasi Central Market',
                style: const TextStyle(
                  color: _gold,
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

class _DriverAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _avatarBg,
            border: Border.all(color: _gold, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.person_rounded, size: 46, color: _darkSlate),
        ),
        Positioned(
          bottom: 4,
          right: 4,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _success,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

class _RatingRow extends StatelessWidget {
  final double rating;
  final int tripCount;
  const _RatingRow({required this.rating, required this.tripCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star_rounded, size: 16, color: _gold),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(2),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '· ${_formatCount(tripCount)} trips',
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(count % 1000 == 0 ? 0 : 3).replaceAll(RegExp(r'\.?0+$'), '')},${(count % 1000).toString().padLeft(3, '0')}';
    }
    return count.toString();
  }
}

class _BadgeRow extends StatelessWidget {
  final bool isVerified;
  final bool isPoliceChecked;
  const _BadgeRow({required this.isVerified, required this.isPoliceChecked});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isVerified) _StatusBadge(
          label: 'Verified',
          icon: Icons.check_circle_rounded,
          color: _success,
          bgColor: _successLight,
        ),
        if (isVerified && isPoliceChecked) const SizedBox(width: 8),
        if (isPoliceChecked) _StatusBadge(
          label: 'Police Checked',
          icon: Icons.shield_rounded,
          color: _gold,
          bgColor: _goldLight,
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;

  const _StatusBadge({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  final String maskedPhone;
  const _PhoneRow({required this.maskedPhone});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.phone_rounded, size: 14, color: _textSecondary),
        const SizedBox(width: 6),
        Text(
          maskedPhone,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}
