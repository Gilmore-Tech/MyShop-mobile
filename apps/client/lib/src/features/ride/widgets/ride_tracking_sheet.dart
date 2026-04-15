import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _success = Color(0xFF27AE60);
const _error = Color(0xFFEB5757);
const _divider = Color(0xFFE0E0E0);
const _darkSlate = Color(0xFF46535D);
const _avatarBg = Color(0xFFE0E6FF);
const _outlinedBorder = Color(0xFFE0E0E0);

class RideTrackingSheet extends StatelessWidget {
  final MatchedDriver driver;
  final ScrollController scrollController;
  final VoidCallback onCancel;
  final VoidCallback onAddStop;

  /// Null while en route; non-null once the driver has arrived. Positive
  /// values are the free-wait countdown, negative values are overtime.
  final int? waitingSeconds;

  /// True once the driver has started the trip. Hides the waiting timer
  /// column and the cancel request action; surfaces a "trip in progress"
  /// banner and the "Add a Stop" action instead.
  final bool isInProgress;

  const RideTrackingSheet({
    super.key,
    required this.driver,
    required this.scrollController,
    required this.onCancel,
    required this.onAddStop,
    this.waitingSeconds,
    this.isInProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    final firstName = driver.name.split(' ').first;
    final isOvertime = !isInProgress &&
        waitingSeconds != null &&
        waitingSeconds! <= 0;
    // Once the trip has started, the waiting timer is no longer relevant.
    final effectiveWaiting = isInProgress ? null : waitingSeconds;

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
      child: SingleChildScrollView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DragHandle(),
            _FareRow(driver: driver, waitingSeconds: effectiveWaiting),
            if (isOvertime) const _OvertimeNotice(),
            if (isInProgress) const _TripInProgressNotice(),
            const Divider(height: 1, thickness: 1, color: _divider),
            _DriverRow(driver: driver),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ChatRow(driverFirstName: firstName),
                  const SizedBox(height: 10),
                  const _SecondaryActions(),
                  const SizedBox(height: 14),
                  const _SafetyNotice(),
                  const SizedBox(height: 18),
                  if (isInProgress)
                    _AddStopButton(onTap: onAddStop)
                  else ...[
                    const Divider(height: 1, thickness: 1, color: _divider),
                    const SizedBox(height: 14),
                    _CancelRequestButton(onTap: onCancel),
                  ],
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Drag handle ───────────────────────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  const _DragHandle();

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
  final int? waitingSeconds;

  const _FareRow({required this.driver, this.waitingSeconds});

  @override
  Widget build(BuildContext context) {
    final showTimer = waitingSeconds != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  driver.activeFareDisplay,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                _PaymentMethod(method: driver.paymentMethod),
              ],
            ),
          ),
          if (showTimer) _WaitingTimer(seconds: waitingSeconds!),
        ],
      ),
    );
  }
}

class _PaymentMethod extends StatelessWidget {
  final String method;
  const _PaymentMethod({required this.method});

  @override
  Widget build(BuildContext context) {
    final isCash = method.toLowerCase() == 'cash';
    final label = isCash ? 'Cash trip' : method;
    final icon = isCash
        ? Icons.payments_rounded
        : Icons.phone_android_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _textSecondary),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Waiting timer (fare-row right column when arrived) ───────────────────────

class _WaitingTimer extends StatelessWidget {
  final int seconds;
  const _WaitingTimer({required this.seconds});

  @override
  Widget build(BuildContext context) {
    final isOvertime = seconds <= 0;
    final absSeconds = seconds.abs();
    final mm = (absSeconds ~/ 60).toString().padLeft(2, '0');
    final ss = (absSeconds % 60).toString().padLeft(2, '0');
    final accent = isOvertime ? _error : _success;
    final prefix = isOvertime ? '+' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$prefix$mm:$ss',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: accent,
            height: 1.1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Waiting for you',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}

// ── Overtime notice ──────────────────────────────────────────────────────────

class _OvertimeNotice extends StatelessWidget {
  const _OvertimeNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFDECEC),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 16, color: _error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Free wait time is up — extra waiting will be added to your fare.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _error,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Trip-in-progress notice ──────────────────────────────────────────────────

class _TripInProgressNotice extends StatelessWidget {
  const _TripInProgressNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFE8F8EF),
      child: Row(
        children: const [
          Icon(Icons.navigation_rounded, size: 16, color: _success),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Trip in progress. Enjoy the ride.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _success,
                height: 1.35,
              ),
            ),
          ),
        ],
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

    return InkWell(
      onTap: () =>
          context.push(AppRoutes.rideDriverFound, extra: driver),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const _DriverAvatar(),
            const SizedBox(width: 12),
            Expanded(child: _DriverMeta(driver: driver)),
            _VehicleInfo(
              vehicleName: shortVehicle,
              plateNumber: driver.plateNumber,
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right_rounded,
                size: 18, color: _textSecondary),
          ],
        ),
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar();

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

// ── Chat + phone row ─────────────────────────────────────────────────────────

class _ChatRow extends StatelessWidget {
  final String driverFirstName;
  const _ChatRow({required this.driverFirstName});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: () {
                // TODO: Navigate to chat screen
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _darkSlate,
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
          ),
        ),
        const SizedBox(width: 10),
        _PhoneCircleButton(onTap: () {}),
      ],
    );
  }
}

class _PhoneCircleButton extends StatelessWidget {
  final VoidCallback onTap;
  const _PhoneCircleButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(color: _outlinedBorder, width: 1.5),
        ),
        child: const Icon(Icons.phone_rounded, size: 20, color: _textPrimary),
      ),
    );
  }
}

// ── Secondary actions ─────────────────────────────────────────────────────────

class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions();

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
  const _SafetyNotice();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Icon(Icons.shield_outlined, size: 15, color: _textSecondary),
        SizedBox(width: 8),
        Expanded(
          child: Text(
            'Your safety is our priority. In-app recording is active for this trip. '
            'Share your live location with family for extra peace of mind.',
            style: TextStyle(
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

// ── Add a stop (only visible once the trip is in progress) ───────────────────

class _AddStopButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStopButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: _darkSlate,
          side: const BorderSide(color: _outlinedBorder, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: const Icon(Icons.add_location_alt_outlined,
            size: 18, color: _darkSlate),
        label: const Text(
          'Add a Stop',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _darkSlate,
          ),
        ),
      ),
    );
  }
}

// ── Cancel request (revealed when the sheet is pulled up) ─────────────────────

class _CancelRequestButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CancelRequestButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: _error,
              side: BorderSide(color: _error.withValues(alpha: 0.5), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.cancel_outlined, size: 18, color: _error),
            label: const Text(
              'Cancel Request',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _error,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Free cancellation within 3 minutes of match.',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}
