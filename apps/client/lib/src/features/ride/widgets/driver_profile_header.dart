import 'package:flutter/material.dart';
import '../providers/ride_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _success = Color(0xFF27AE60);
const _avatarBg = Color(0xFFE0E6FF);
const _darkSlate = Color(0xFF46535D);
const _border = Color(0xFFE0E0E0);
const _chipBg = Color(0xFFF3F5F6);

/// Arrival headline + bordered driver identity card stacked vertically.
class DriverProfileHeader extends StatelessWidget {
  final MatchedDriver driver;

  const DriverProfileHeader({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _ArrivalHeadline(driverName: driver.name),
        const SizedBox(height: 16),
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
        const SizedBox(height: 6),
        RichText(
          textAlign: TextAlign.center,
          text: const TextSpan(
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: _textSecondary,
              height: 1.4,
            ),
            children: [
              TextSpan(text: "We've found a highly-rated driver near\n"),
              TextSpan(
                text: 'Kumasi Central Market',
                style: TextStyle(
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

class _DriverIdentityCard extends StatelessWidget {
  final MatchedDriver driver;
  const _DriverIdentityCard({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(60, 24, 60, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          const _DriverAvatar(),
          const SizedBox(height: 12),
          Text(
            driver.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          _RatingRow(rating: driver.rating, tripCount: driver.tripCount),
          const SizedBox(height: 14),
          _BadgeRow(
            isVerified: driver.isVerified,
            isPoliceChecked: driver.isPoliceChecked,
          ),
          const SizedBox(height: 14),
          _PhoneChip(maskedPhone: driver.maskedPhone),
        ],
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _avatarBg,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.person_rounded, size: 42, color: _darkSlate),
        ),
        Positioned(
          bottom: 2,
          right: 2,
          child: Container(
            width: 14,
            height: 14,
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
        const Icon(Icons.star_rounded, size: 15, color: _gold),
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isVerified)
          const _OutlinedBadge(
            label: 'Verified',
            icon: Icons.check_circle_rounded,
            color: _success,
          ),
        if (isVerified && isPoliceChecked) const SizedBox(width: 8),
        if (isPoliceChecked)
          const _OutlinedBadge(
            label: 'Police Checked',
            icon: Icons.shield_rounded,
            color: _textPrimary,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
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

class _PhoneChip extends StatelessWidget {
  final String maskedPhone;
  const _PhoneChip({required this.maskedPhone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _chipBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.phone_rounded, size: 13, color: _textSecondary),
          const SizedBox(width: 6),
          Text(
            maskedPhone,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
