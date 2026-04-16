import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';

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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
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
            const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
            _DriverRow(driver: driver),
            SizedBox(height: h * 0.012),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.041),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ChatRow(driverFirstName: firstName),
                  SizedBox(height: h * 0.012),
                  const _SecondaryActions(),
                  SizedBox(height: h * 0.017),
                  const _SafetyNotice(),
                  SizedBox(height: h * 0.021),
                  if (isInProgress)
                    _AddStopButton(onTap: onAddStop)
                  else ...[
                    const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
                    SizedBox(height: h * 0.017),
                    _CancelRequestButton(onTap: onCancel),
                  ],
                  SizedBox(height: h * 0.033),
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(top: h * 0.012, bottom: h * 0.007),
      child: Center(
        child: Container(
          width:  w * 0.103,
          height: h * 0.005,
          decoration: BoxDecoration(
            color: MyShopColors.divider,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final showTimer = waitingSeconds != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(w * 0.041, h * 0.009, w * 0.041, h * 0.017),
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
                  style: TextStyle(
                    fontSize: w * 0.067,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: h * 0.007),
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
    final w = MediaQuery.sizeOf(context).width;
    final isCash = method.toLowerCase() == 'cash';
    final label = isCash ? 'Cash trip' : method;
    final icon = isCash
        ? Icons.payments_rounded
        : Icons.phone_android_rounded;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: w * 0.036, color: MyShopColors.textSecondary),
        SizedBox(width: w * 0.015),
        Text(
          label,
          style: TextStyle(
            fontSize: w * 0.031,
            fontWeight: FontWeight.w500,
            color: MyShopColors.textSecondary,
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
    final accent = isOvertime ? MyShopColors.error : MyShopColors.success;
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
            color: MyShopColors.textSecondary,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.012),
      color: const Color(0xFFFDECEC),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: w * 0.041, color: MyShopColors.error),
          SizedBox(width: w * 0.021),
          Expanded(
            child: Text(
              'Free wait time is up — extra waiting will be added to your fare.',
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w500,
                color: MyShopColors.error,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.012),
      color: MyShopColors.successLight,
      child: Row(
        children: [
          Icon(Icons.navigation_rounded, size: w * 0.041, color: MyShopColors.success),
          SizedBox(width: w * 0.021),
          Expanded(
            child: Text(
              'Trip in progress. Enjoy the ride.',
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w500,
                color: MyShopColors.success,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final shortVehicle = driver.vehicleShortName.isNotEmpty
        ? driver.vehicleShortName
        : driver.vehicle.split(' ').take(2).join(' ');

    return InkWell(
      onTap: () =>
          context.push(AppRoutes.rideDriverFound, extra: driver),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.017,
        ),
        child: Row(
          children: [
            const _DriverAvatar(),
            SizedBox(width: w * 0.031),
            Expanded(child: _DriverMeta(driver: driver)),
            _VehicleInfo(
              vehicleName: shortVehicle,
              plateNumber: driver.plateNumber,
            ),
            SizedBox(width: w * 0.015),
            Icon(
              Icons.chevron_right_rounded,
              size: w * 0.046,
              color: MyShopColors.textSecondary,
            ),
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
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width:  w * 0.123,
      height: w * 0.123,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MyShopColors.avatarPlaceholder,
        border: Border.all(color: MyShopColors.primaryGold, width: 1.5),
      ),
      child: Icon(Icons.person_rounded, size: w * 0.067, color: MyShopColors.darkSlate),
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
            color: MyShopColors.textPrimary,
          ),
        ),
        SizedBox(height: h * 0.004),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_rounded, size: w * 0.033, color: MyShopColors.primaryGold),
            SizedBox(width: w * 0.008),
            Text(
              driver.rating.toStringAsFixed(1),
              style: TextStyle(
                fontSize: w * 0.031,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textPrimary,
              ),
            ),
            if (driver.isVerified) ...[
              SizedBox(width: w * 0.021),
              Text(
                '· Verified',
                style: TextStyle(
                  fontSize: w * 0.031,
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.success,
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
            color: MyShopColors.textSecondary,
          ),
        ),
        SizedBox(height: h * 0.004),
        Text(
          plateNumber,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: h * 0.059,
            child: ElevatedButton.icon(
              onPressed: () {
                // TODO: Navigate to chat screen
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.darkSlate,
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
          ),
        ),
        SizedBox(width: w * 0.026),
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
          border: Border.all(color: MyShopColors.divider, width: 1.5),
        ),
        child: const Icon(Icons.phone_rounded, size: 20, color: MyShopColors.textPrimary),
      ),
    );
  }
}

// ── Secondary actions ─────────────────────────────────────────────────────────

class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions();

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
        foregroundColor: MyShopColors.textPrimary,
        side: const BorderSide(color: MyShopColors.divider, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(w * 0.026),
        ),
        padding: EdgeInsets.symmetric(vertical: h * 0.014),
      ),
      icon: Icon(icon, size: w * 0.041, color: MyShopColors.textPrimary),
      label: Text(
        label,
        style: TextStyle(
          fontSize: w * 0.033,
          fontWeight: FontWeight.w600,
          color: MyShopColors.textPrimary,
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
    final w = MediaQuery.sizeOf(context).width;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.shield_outlined, size: w * 0.038, color: MyShopColors.textSecondary),
        SizedBox(width: w * 0.021),
        Expanded(
          child: Text(
            'Your safety is our priority. In-app recording is active for this trip. '
            'Share your live location with family for extra peace of mind.',
            style: TextStyle(
              fontSize: w * 0.028,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
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
          foregroundColor: MyShopColors.darkSlate,
          side: const BorderSide(color: MyShopColors.divider, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: const Icon(Icons.add_location_alt_outlined,
            size: 18, color: MyShopColors.darkSlate),
        label: const Text(
          'Add a Stop',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MyShopColors.darkSlate,
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
              foregroundColor: MyShopColors.error,
              side: BorderSide(color: MyShopColors.error.withValues(alpha: 0.5), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.cancel_outlined, size: 18, color: MyShopColors.error),
            label: const Text(
              'Cancel Request',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: MyShopColors.error,
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
            color: MyShopColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
