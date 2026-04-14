import 'package:flutter/material.dart';
import '../providers/ride_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _goldLight = Color(0xFFFFF8EC);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _success = Color(0xFF27AE60);
const _divider = Color(0xFFE0E0E0);
const _darkSlate = Color(0xFF46535D);
const _avatarBg = Color(0xFFE0E6FF);
const _buttonBg = Color(0xFF1C1C1E);
const _outlinedBorder = Color(0xFFE0E0E0);

class RideTrackingSheet extends StatelessWidget {
  final MatchedDriver driver;

  const RideTrackingSheet({super.key, required this.driver});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _DragHandle(),
          _FareRow(driver: driver),
          const Divider(height: 1, thickness: 1, color: _divider),
          _DriverRow(driver: driver),
          SizedBox(height: h * 0.017),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.041),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatButton(driverFirstName: driver.name.split(' ').first),
                SizedBox(height: h * 0.012),
                _SecondaryActions(),
                SizedBox(height: h * 0.017),
                _SafetyNotice(),
                SizedBox(height: h * 0.024),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drag handle ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(top: h * 0.012, bottom: h * 0.007),
      child: Center(
        child: Container(
          width:  w * 0.103,
          height: h * 0.005,
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// ── Fare row ──────────────────────────────────────────────────────────────────

class _FareRow extends StatelessWidget {
  final MatchedDriver driver;
  const _FareRow({required this.driver});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.041, h * 0.009, w * 0.041, h * 0.017),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            driver.activeFareDisplay,
            style: TextStyle(
              fontSize: w * 0.067,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const Spacer(),
          _PaymentBadge(method: driver.paymentMethod),
        ],
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  final String method;
  const _PaymentBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final isCash = method.toLowerCase() == 'cash';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.031, vertical: h * 0.006),
      decoration: BoxDecoration(
        color: isCash ? _goldLight : const Color(0xFFE8F8EF),
        borderRadius: BorderRadius.circular(w * 0.051),
        border: Border.all(
          color: isCash
              ? _gold.withValues(alpha: 0.4)
              : _success.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        isCash ? 'CASH TRIP' : method.toUpperCase(),
        style: TextStyle(
          fontSize: w * 0.026,
          fontWeight: FontWeight.w800,
          color: isCash ? _gold : _success,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Driver info row ───────────────────────────────────────────────────────────

class _DriverRow extends StatelessWidget {
  final MatchedDriver driver;
  const _DriverRow({required this.driver});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final shortVehicle = driver.vehicleShortName.isNotEmpty
        ? driver.vehicleShortName
        : driver.vehicle.split(' ').take(2).join(' ');

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.017),
      child: Row(
        children: [
          _DriverAvatar(),
          SizedBox(width: w * 0.031),
          Expanded(child: _DriverMeta(driver: driver)),
          _VehicleInfo(
            vehicleName: shortVehicle,
            plateNumber: driver.plateNumber,
          ),
        ],
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width:  w * 0.123,
      height: w * 0.123,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _avatarBg,
        border: Border.all(color: _gold, width: 1.5),
      ),
      child: Icon(Icons.person_rounded, size: w * 0.067, color: _darkSlate),
    );
  }
}

class _DriverMeta extends StatelessWidget {
  final MatchedDriver driver;
  const _DriverMeta({required this.driver});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          driver.name,
          style: TextStyle(
            fontSize: w * 0.036,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        SizedBox(height: h * 0.004),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: w * 0.033, color: _gold),
            SizedBox(width: w * 0.008),
            Text(
              driver.rating.toStringAsFixed(1),
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            if (driver.isVerified) ...[
              SizedBox(width: w * 0.021),
              Text(
                '· Verified',
                style: TextStyle(
                  fontSize: w * 0.031,
                  fontWeight: FontWeight.w500,
                  color: _success,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _VehicleInfo extends StatelessWidget {
  final String vehicleName;
  final String plateNumber;

  const _VehicleInfo({required this.vehicleName, required this.plateNumber});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          vehicleName,
          style: TextStyle(
            fontSize: w * 0.028,
            fontWeight: FontWeight.w400,
            color: _textSecondary,
          ),
        ),
        SizedBox(height: h * 0.004),
        Text(
          plateNumber,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Action buttons ────────────────────────────────────────────────────────────

class _ChatButton extends StatelessWidget {
  final String driverFirstName;
  const _ChatButton({required this.driverFirstName});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return SizedBox(
      width: double.infinity,
      height: h * 0.059,
      child: ElevatedButton.icon(
        onPressed: () {
          // TODO: Navigate to chat screen
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _buttonBg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(w * 0.026),
          ),
          elevation: 0,
        ),
        icon: Icon(Icons.chat_bubble_rounded, size: w * 0.046),
        label: Text(
          'Chat with $driverFirstName',
          style: TextStyle(
            fontSize: w * 0.036,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _SecondaryActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Row(
      children: [
        Expanded(
          child: _OutlinedActionButton(
            icon: Icons.share_rounded,
            label: 'Share Trip',
            onTap: () {},
          ),
        ),
        SizedBox(width: w * 0.026),
        Expanded(
          child: _OutlinedActionButton(
            icon: Icons.schedule_rounded,
            label: 'Send ETA',
            onTap: () {},
          ),
        ),
      ],
    );
  }
}

class _OutlinedActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OutlinedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _textPrimary,
        side: const BorderSide(color: _outlinedBorder, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(w * 0.026),
        ),
        padding: EdgeInsets.symmetric(vertical: h * 0.014),
      ),
      icon: Icon(icon, size: w * 0.041, color: _textPrimary),
      label: Text(
        label,
        style: TextStyle(
          fontSize: w * 0.033,
          fontWeight: FontWeight.w600,
          color: _textPrimary,
        ),
      ),
    );
  }
}

// ── Safety notice ─────────────────────────────────────────────────────────────

class _SafetyNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: w * 0.038, color: _textSecondary),
        SizedBox(width: w * 0.021),
        Expanded(
          child: Text(
            'Your safety is our priority. In-app recording is active for this trip. '
            'Share your live location with family for extra peace of mind.',
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w400,
              color: _textSecondary,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}
