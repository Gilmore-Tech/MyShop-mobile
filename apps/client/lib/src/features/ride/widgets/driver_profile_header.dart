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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.062, vertical: h * 0.024),
      child: Column(
        children: [
          _ArrivalHeadline(driverName: driver.name),
          SizedBox(height: h * 0.024),
          _DriverAvatar(),
          SizedBox(height: h * 0.017),
          Text(
            driver.name,
            style: TextStyle(
              fontSize: w * 0.051,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          SizedBox(height: h * 0.007),
          _RatingRow(rating: driver.rating, tripCount: driver.tripCount),
          SizedBox(height: h * 0.012),
          _BadgeRow(
            isVerified: driver.isVerified,
            isPoliceChecked: driver.isPoliceChecked,
          ),
          SizedBox(height: h * 0.012),
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
            color: _textPrimary,
          ),
        ),
        SizedBox(height: h * 0.005),
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            style: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w400,
              color: _textSecondary,
            ),
            children: [
              const TextSpan(text: "We've found a highly-rated driver near\n"),
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

class _DriverAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width:  w * 0.215,
          height: w * 0.215,
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
          child: Icon(Icons.person_rounded, size: w * 0.118, color: _darkSlate),
        ),
        Positioned(
          bottom: w * 0.010,
          right:  w * 0.010,
          child: Container(
            width:  w * 0.041,
            height: w * 0.041,
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
    final w = MediaQuery.sizeOf(context).width;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: w * 0.041, color: _gold),
        SizedBox(width: w * 0.010),
        Text(
          rating.toStringAsFixed(2),
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        SizedBox(width: w * 0.015),
        Text(
          '· ${_formatCount(tripCount)} trips',
          style: TextStyle(
            fontSize: w * 0.033,
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
    final w = MediaQuery.sizeOf(context).width;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isVerified) _StatusBadge(
          label: 'Verified',
          icon: Icons.check_circle_rounded,
          color: _success,
          bgColor: _successLight,
        ),
        if (isVerified && isPoliceChecked) SizedBox(width: w * 0.021),
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.026, vertical: h * 0.006),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(w * 0.051),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: w * 0.031, color: color),
          SizedBox(width: w * 0.010),
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

class _PhoneRow extends StatelessWidget {
  final String maskedPhone;
  const _PhoneRow({required this.maskedPhone});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.phone_rounded, size: w * 0.036, color: _textSecondary),
        SizedBox(width: w * 0.015),
        Text(
          maskedPhone,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w500,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}
