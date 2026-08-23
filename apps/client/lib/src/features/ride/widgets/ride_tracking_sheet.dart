import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart' show ChatBookingType;
import 'package:shared_ui/shared_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/chat/chat_entry_button.dart';
import '../../calls/helpers/start_in_app_call.dart';
import '../providers/ride_payment_method_provider.dart';
import '../providers/ride_provider.dart';

class RideTrackingSheet extends StatelessWidget {
  final MatchedDriver driver;
  final ScrollController scrollController;
  final VoidCallback onCancel;

  /// Null while en route; non-null once the driver has arrived. Positive
  /// values are the free-wait countdown, negative values are overtime.
  final int? waitingSeconds;

  /// True once the driver has started the trip. Hides the waiting timer
  /// column; the "trip in progress" banner surfaces in its place.
  /// Multi-stop / "Add a stop" is deferred to v1.1, so there's no
  /// in-trip CTA right now.
  final bool isInProgress;

  /// Controls Cancel Request visibility. The caller gates this on the
  /// active ride phase being `enRoute` or `arrived` — once the trip
  /// starts (or completes / cancels) the button hides. Without this
  /// gate the button used to render even on a `completed` ride for the
  /// brief frame before navigation away, which surprised users into
  /// thinking the ride was still cancellable.
  final bool canCancel;

  const RideTrackingSheet({
    super.key,
    required this.driver,
    required this.scrollController,
    required this.onCancel,
    this.waitingSeconds,
    this.isInProgress = false,
    this.canCancel = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final firstName = driver.name.split(' ').first;
    final isOvertime =
        !isInProgress && waitingSeconds != null && waitingSeconds! <= 0;
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
                  _ChatRow(
                    driverFirstName: firstName,
                    driverFullName: driver.name,
                  ),
                  SizedBox(height: h * 0.017),
                  if (isInProgress) ...[
                    const Divider(
                        height: 1, thickness: 1, color: MyShopColors.divider),
                    SizedBox(height: h * 0.017),
                    const _AddStopButton(),
                    SizedBox(height: h * 0.017),
                  ],
                  const _SafetyNotice(),
                  SizedBox(height: h * 0.021),
                  // Cancel Request is only relevant while the driver is
                  // still on the way (enRoute) or waiting at pickup
                  // (arrived). Once the trip starts, completes, or is
                  // cancelled by the other party, the rider's cancel
                  // action no longer applies — the previous gate of
                  // `!isInProgress` left the button visible on a
                  // `completed` phase for the brief frame before the
                  // tracking-screen listener navigated to /ride-complete.
                  if (canCancel) ...[
                    const Divider(
                        height: 1, thickness: 1, color: MyShopColors.divider),
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
          width: w * 0.103,
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
                if ((driver.toll?.amountPesewas ?? 0) > 0) ...[
                  SizedBox(height: h * 0.004),
                  Text(
                    '${driver.toll!.label}: ${driver.tollDisplay} included',
                    key: const Key('active-ride-toll-line'),
                    style: TextStyle(
                      fontSize: w * 0.029,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
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
    // `method` here is the raw `paymentMethod` field off the snapshot
    // (e.g. `cash` / `momo_mtn`). Translate to display copy via the same
    // helper that powers the fare-estimate selector and the receipt — one
    // source of truth keeps "Cash trip" / "MTN Mobile Money" consistent.
    final isCash = method.toLowerCase() == 'cash';
    final label = isCash ? 'Cash trip' : formatRidePaymentMethodLabel(method);
    final icon = isCash ? Icons.payments_rounded : Icons.phone_android_rounded;
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
          Icon(Icons.info_outline_rounded,
              size: w * 0.041, color: MyShopColors.error),
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
          Icon(Icons.navigation_rounded,
              size: w * 0.041, color: MyShopColors.success),
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
      onTap: () => context.push(AppRoutes.rideDriverFound, extra: driver),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.017,
        ),
        child: Row(
          children: [
            _DriverAvatar(photoUrl: driver.photoUrl),
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
  const _DriverAvatar({required this.photoUrl});
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final size = w * 0.123;
    final placeholder = Icon(
      Icons.person_rounded,
      size: w * 0.067,
      color: MyShopColors.darkSlate,
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MyShopColors.avatarPlaceholder,
        border: Border.all(color: MyShopColors.primaryGold, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: photoUrl.isEmpty
          ? placeholder
          : CachedNetworkImage(
              imageUrl: photoUrl,
              fit: BoxFit.cover,
              memCacheWidth: (size * 3).round(),
              memCacheHeight: (size * 3).round(),
              placeholder: (_, __) => placeholder,
              errorWidget: (_, __, ___) => placeholder,
            ),
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
            Icon(
              Icons.star_rounded,
              size: w * 0.033,
              color: driver.rating != null
                  ? MyShopColors.primaryGold
                  : MyShopColors.textSecondary,
            ),
            SizedBox(width: w * 0.008),
            Text(
              driver.rating?.toStringAsFixed(1) ?? 'New',
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

class _ChatRow extends ConsumerWidget {
  final String driverFirstName;
  final String driverFullName;
  const _ChatRow({
    required this.driverFirstName,
    required this.driverFullName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rideId = ref.watch(activeRideIdProvider) ?? '';
    final phone = ref.watch(matchedDriverProvider)?.phone ?? '';
    final chat = ChatEntryButton(
      bookingType: ChatBookingType.ride,
      bookingId: rideId,
      label: 'Chat with $driverFirstName',
      peerName: driverFullName,
      peerStatus: 'On your trip',
    );
    // In-app calling is booking-scoped and remains available even when the
    // optional public phone number is absent. When a number is present the
    // call button offers both in-app and regular phone calls.
    return Row(
      children: [
        Expanded(child: chat),
        const SizedBox(width: 10),
        MyShopCallButton(
          phoneNumber: phone,
          size: 48,
          semanticLabel: 'Call driver',
          onInAppCall: () {
            unawaited(
              startClientInAppCall(
                context,
                ref,
                bookingType: 'ride',
                bookingId: rideId,
              ),
            );
          },
        ),
      ],
    );
  }
}

// ── Safety notice ─────────────────────────────────────────────────────────────

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.shield_outlined,
                size: w * 0.038, color: MyShopColors.textSecondary),
            SizedBox(width: w * 0.021),
            Expanded(
              child: Text(
                'Your safety is our priority. Use SOS to record an emergency alert '
                'and open the phone dialer. Share your live location with family '
                'for extra peace of mind.',
                style: TextStyle(
                  fontSize: w * 0.028,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: w * 0.021),
        Padding(
          padding: EdgeInsets.only(left: w * 0.059),
          child: GestureDetector(
            onTap: () => context.push(AppRoutes.safetyShare),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.ios_share_rounded,
                    size: w * 0.040, color: MyShopColors.primaryGold),
                SizedBox(width: w * 0.016),
                Text(
                  'Share live location',
                  style: TextStyle(
                    fontSize: w * 0.030,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.primaryGold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Add stop ─────────────────────────────────────────────────────────────────

class _AddStopButton extends StatelessWidget {
  const _AddStopButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: () => context.push(AppRoutes.rideStops),
        style: OutlinedButton.styleFrom(
          foregroundColor: MyShopColors.primaryGoldDark,
          side: BorderSide(
            color: MyShopColors.primaryGold.withValues(alpha: 0.55),
            width: 1.5,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: const Icon(Icons.add_location_alt_outlined,
            size: 18, color: MyShopColors.primaryGoldDark),
        label: const Text(
          'Add a stop',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: MyShopColors.primaryGoldDark,
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
              side: BorderSide(
                  color: MyShopColors.error.withValues(alpha: 0.5), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.cancel_outlined,
                size: 18, color: MyShopColors.error),
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
      ],
    );
  }
}
