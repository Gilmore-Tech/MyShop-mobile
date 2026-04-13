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
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatButton(driverFirstName: driver.name.split(' ').first),
                const SizedBox(height: 10),
                _SecondaryActions(),
                const SizedBox(height: 14),
                _SafetyNotice(),
                const SizedBox(height: 20),
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
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            driver.activeFareDisplay,
            style: const TextStyle(
              fontSize: 26,
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
    final isCash = method.toLowerCase() == 'cash';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: isCash ? _goldLight : const Color(0xFFE8F8EF),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCash
              ? _gold.withValues(alpha: 0.4)
              : _success.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        isCash ? 'CASH TRIP' : method.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
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
    final shortVehicle = driver.vehicleShortName.isNotEmpty
        ? driver.vehicleShortName
        : driver.vehicle.split(' ').take(2).join(' ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          _DriverAvatar(),
          const SizedBox(width: 12),
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
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _avatarBg,
        border: Border.all(color: _gold, width: 1.5),
      ),
      child: const Icon(Icons.person_rounded, size: 26, color: _darkSlate),
    );
  }
}

class _DriverMeta extends StatelessWidget {
  final MatchedDriver driver;
  const _DriverMeta({required this.driver});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          driver.name,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star_rounded, size: 13, color: _gold),
            const SizedBox(width: 3),
            Text(
              driver.rating.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _textPrimary,
              ),
            ),
            if (driver.isVerified) ...[
              const SizedBox(width: 8),
              const Text(
                '· Verified',
                style: TextStyle(
                  fontSize: 12,
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
    // Format plate: "GR-4557-23" → "GR 492 · 22" style (display dots)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          vehicleName,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: _textSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          plateNumber,
          style: const TextStyle(
            fontSize: 13,
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
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: () {
          // TODO: Navigate to chat screen
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: _buttonBg,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
        ),
        icon: const Icon(Icons.chat_bubble_rounded, size: 18),
        label: Text(
          'Chat with $driverFirstName',
          style: const TextStyle(
            fontSize: 14,
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
    return Row(
      children: [
        Expanded(
          child: _OutlinedActionButton(
            icon: Icons.share_rounded,
            label: 'Share Trip',
            onTap: () {},
          ),
        ),
        const SizedBox(width: 10),
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
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _textPrimary,
        side: const BorderSide(color: _outlinedBorder, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: Icon(icon, size: 16, color: _textPrimary),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, size: 15, color: _textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Your safety is our priority. In-app recording is active for this trip. '
            'Share your live location with family for extra peace of mind.',
            style: const TextStyle(
              fontSize: 11,
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
