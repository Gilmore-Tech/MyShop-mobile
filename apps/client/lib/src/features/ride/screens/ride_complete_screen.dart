import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_provider.dart';
import '../widgets/rate_ride_sheet.dart';

// ── Viewport ratios (derived from 390×844 reference design) ───────────────────
//
// All spatial values are computed as fractions of the live screen dimensions so
// the layout scales correctly across every phone size and orientation without
// any conditional breakpoints.
//
// Width-relative  → horizontal padding, avatar size, icon size, gap widths
// Height-relative → vertical spacing, input/button heights, nav bar height

// ── Formatter ─────────────────────────────────────────────────────────────────

String _fmtGhs(int pesewas) {
  final ghs = pesewas / 100;
  return 'GHS ${ghs.toStringAsFixed(2)}';
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// PRD 4.3 — Ride Completion: fare receipt, driver profile, optional tip.
/// API: POST /v1/payments/:id/tip (EDD § Payments — zero commission, auto-retry)
class RideCompleteScreen extends ConsumerStatefulWidget {
  const RideCompleteScreen({super.key});

  @override
  ConsumerState<RideCompleteScreen> createState() => _RideCompleteScreenState();
}

class _RideCompleteScreenState extends ConsumerState<RideCompleteScreen> {
  final _customTipController = TextEditingController();

  /// One-shot guard so the OK CTA can't queue a second rating sheet while
  /// the first is animating open.
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    // PRD 4.3 — driver marks ride complete → client sees the trip SUMMARY
    // first. The rating sheet must NOT auto-open over it (it used to cover
    // the summary on frame 1, so riders never saw their fare); it opens when
    // the rider taps OK, and the receipt follows the rating.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(rideReceiptProvider) == null) {
        // Edge case: deep-linked here without the snapshot having landed —
        // fall back to home so the rider isn't stuck on a half-rendered
        // screen.
        context.go(AppRoutes.home);
      }
    });
  }

  /// Summary acknowledged → rate the driver → land on the receipt.
  /// fromCompletion=true makes the receipt's back button return home.
  Future<void> _acknowledgeSummary() async {
    if (_advancing || !mounted) return;
    _advancing = true;
    final receipt = ref.read(rideReceiptProvider);
    if (receipt == null) {
      context.go(AppRoutes.home);
      return;
    }
    await showRateRideSheet(
      context,
      rideId: receipt.rideId,
      driverFirstName: receipt.driverFirstName,
    );
    if (!mounted) return;
    context.pushReplacement(
      AppRoutes.rideReceiptPath(receipt.rideId),
      extra: true,
    );
  }

  @override
  void dispose() {
    _customTipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipt = ref.watch(rideReceiptProvider);
    final tipState = ref.watch(tipStateProvider);
    final h = MediaQuery.sizeOf(context).height;

    if (receipt == null) {
      // Snapshot hasn't arrived yet — render a transient loading state
      // rather than crashing on null fields. The post-frame callback above
      // will redirect home if it stays null.
      return const Scaffold(
        backgroundColor: MyShopColors.offWhite,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(receipt: receipt),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: h * 0.014), // ~12dp
                    _DriverCard(receipt: receipt),
                    SizedBox(height: h * 0.009), // ~8dp
                    _RouteCard(receipt: receipt),
                    SizedBox(height: h * 0.009),
                    _FareBreakdownCard(receipt: receipt),
                    SizedBox(height: h * 0.009),
                    _TipSection(
                      receipt: receipt,
                      tipState: tipState,
                      customController: _customTipController,
                      onPresetSelected: (pesewas) {
                        _customTipController.clear();
                        ref
                            .read(tipStateProvider.notifier)
                            .selectPreset(pesewas);
                      },
                      onCustomChanged: (text) =>
                          ref.read(tipStateProvider.notifier).setCustom(text),
                      onConfirm: tipState.hasAmount
                          ? () => _submitTip(context, receipt, tipState)
                          : null,
                    ),
                    SizedBox(height: h * 0.019), // ~16dp
                    // Summary acknowledgement — advances to rating, then the
                    // receipt. The rider always gets to read the fare first.
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: MediaQuery.sizeOf(context).width * 0.041,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: h * 0.062, // ~52dp
                        child: ElevatedButton(
                          onPressed: _acknowledgeSummary,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: MyShopColors.primaryGold,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                MediaQuery.sizeOf(context).width * 0.021,
                              ),
                            ),
                          ),
                          child: Text(
                            'OK',
                            style: TextStyle(
                              fontSize:
                                  MediaQuery.sizeOf(context).width * 0.036,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: h * 0.028), // ~24dp
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitTip(BuildContext context, RideReceipt receipt, TipState tip) {
    // TODO: POST /v1/payments/:id/tip — wire up once API client is available
    MyShopToast.show(context,
        message:
            'Tip of ${_fmtGhs(tip.effectivePesewas)} sent to ${receipt.driverFirstName}!');
    ref.read(tipStateProvider.notifier).reset();
    _customTipController.clear();
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final RideReceipt receipt;
  const _Header({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041, // ~16dp
        vertical: h * 0.018, // ~15dp
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Arrived Safe',
            style: TextStyle(
              fontSize: w * 0.051, // ~20dp
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          Text(
            receipt.completedAt,
            style: TextStyle(
              fontSize: w * 0.031, // ~12dp
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Driver Card ───────────────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  final RideReceipt receipt;
  const _DriverCard({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;

    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.all(w * 0.041), // ~16dp
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _DriverAvatar(w: w),
          SizedBox(width: w * 0.036), // ~14dp
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  receipt.driverName,
                  style: TextStyle(
                    fontSize: w * 0.041, // ~16dp
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                SizedBox(height: w * 0.008), // ~3dp
                Text(
                  receipt.vehicleDisplay,
                  style: TextStyle(
                    fontSize: w * 0.031, // ~12dp
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                  ),
                ),
                if (receipt.isDriverVerified) ...[
                  SizedBox(height: w * 0.021), // ~8dp
                  _VerifiedBadge(w: w),
                ],
              ],
            ),
          ),
          _RatingPill(rating: receipt.driverRating, w: w),
        ],
      ),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  final double w;
  const _DriverAvatar({required this.w});

  @override
  Widget build(BuildContext context) {
    final size = w * 0.144; // ~56dp
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MyShopColors.avatarPlaceholder,
        border: Border.all(
            color: MyShopColors.primaryGold, width: w * 0.005), // ~2dp
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: w * 0.021,
            offset: Offset(0, w * 0.005),
          ),
        ],
      ),
      child: Icon(
        Icons.person_rounded,
        size: w * 0.077, // ~30dp
        color: MyShopColors.darkSlate,
      ),
    );
  }
}

class _VerifiedBadge extends StatelessWidget {
  final double w;
  const _VerifiedBadge({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.026, // ~10dp
        vertical: w * 0.010, // ~4dp
      ),
      decoration: BoxDecoration(
        color: MyShopColors.successLight,
        borderRadius: BorderRadius.circular(w * 0.051), // ~20dp
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: w * 0.031, // ~12dp
            color: MyShopColors.success,
          ),
          SizedBox(width: w * 0.010),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: w * 0.028, // ~11dp
              fontWeight: FontWeight.w600,
              color: MyShopColors.success,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  /// Null when the driver has no revealed ratings yet — rendered as
  /// "New" rather than a fake numerical score.
  final double? rating;
  final double w;
  const _RatingPill({required this.rating, required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star_rounded,
          size: w * 0.041,
          color: rating != null
              ? MyShopColors.primaryGold
              : MyShopColors.textSecondary,
        ),
        SizedBox(width: w * 0.008),
        Text(
          rating?.toStringAsFixed(1) ?? 'New',
          style: TextStyle(
            fontSize: w * 0.036, // ~14dp
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Route Card ────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final RideReceipt receipt;
  const _RouteCard({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    // Icon is w*0.051 wide — connector sits at its horizontal centre
    final connectorLeft = (w * 0.051 / 2) - 0.75;

    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041, // ~16dp
        vertical: h * 0.017, // ~14dp
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RouteStop(
            icon: Icons.radio_button_checked,
            iconColor: MyShopColors.textSecondary,
            typeLabel: 'PICKUP',
            address: receipt.pickupAddress,
            w: w,
          ),
          Padding(
            padding: EdgeInsets.only(left: connectorLeft),
            child: Container(
              width: 1.5,
              height: h * 0.019, // ~16dp
              color: MyShopColors.divider,
            ),
          ),
          _RouteStop(
            icon: Icons.location_on_rounded,
            iconColor: MyShopColors.primaryGold,
            typeLabel: 'DESTINATION',
            address: receipt.dropoffAddress,
            w: w,
          ),
        ],
      ),
    );
  }
}

class _RouteStop extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String typeLabel;
  final String address;
  final double w;

  const _RouteStop({
    required this.icon,
    required this.iconColor,
    required this.typeLabel,
    required this.address,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: w * 0.051, color: iconColor), // ~20dp
        SizedBox(width: w * 0.031), // ~12dp
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: w * 0.026, // ~10dp
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(height: w * 0.005),
              Text(
                address,
                style: TextStyle(
                  fontSize: w * 0.033, // ~13dp
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Fare Breakdown Card ───────────────────────────────────────────────────────

class _FareBreakdownCard extends StatelessWidget {
  final RideReceipt receipt;
  const _FareBreakdownCard({required this.receipt});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final pad = w * 0.041; // ~16dp

    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FareBreakdownHeader(rideId: receipt.rideId, w: w),
          SizedBox(height: h * 0.017), // ~14dp
          _FareLineItem(
            label: 'Base Fare',
            amount: _fmtGhs(receipt.baseFarePesewas),
            w: w,
          ),
          SizedBox(height: h * 0.012), // ~10dp
          _FareLineItem(
            label: 'Distance (${receipt.distanceKm.toStringAsFixed(1)} km)',
            amount: _fmtGhs(receipt.distanceFarePesewas),
            w: w,
          ),
          SizedBox(height: h * 0.012),
          _FareLineItem(
            label: 'Time (${receipt.durationMins} mins)',
            amount: _fmtGhs(receipt.timeFarePesewas),
            w: w,
          ),
          SizedBox(height: h * 0.012),
          _FareLineItem(
            label: '⚡ Surge Pricing (${receipt.surgeMultiplier}x)',
            amount: _fmtGhs(receipt.surgeFarePesewas),
            w: w,
          ),
          SizedBox(height: h * 0.017),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.017),
          _FareLineItem(
            label: 'Subtotal',
            amount: _fmtGhs(receipt.subtotalPesewas),
            w: w,
          ),
          SizedBox(height: h * 0.012),
          _FareLineItem(
            label: 'Taxes & Levies',
            amount: _fmtGhs(receipt.taxesPesewas),
            w: w,
          ),
          if ((receipt.toll?.amountPesewas ?? 0) > 0) ...[
            SizedBox(height: h * 0.012),
            _FareLineItem(
              label: receipt.toll!.label,
              amount: _fmtGhs(receipt.toll!.amountPesewas),
              w: w,
            ),
          ],
          if (receipt.promoDiscountPesewas > 0) ...[
            SizedBox(height: h * 0.012),
            _FareLineItem(
              label: 'Promotional Discount',
              amount: '- ${_fmtGhs(receipt.promoDiscountPesewas)}',
              amountColor: MyShopColors.error,
              w: w,
            ),
          ],
          if (receipt.loyaltyDiscountPesewas > 0) ...[
            SizedBox(height: h * 0.012),
            _FareLineItem(
              label: 'Loyalty Discount',
              amount: '- ${_fmtGhs(receipt.loyaltyDiscountPesewas)}',
              amountColor: MyShopColors.error,
              w: w,
            ),
          ],
          SizedBox(height: h * 0.017),
          const Divider(height: 2, thickness: 2, color: MyShopColors.divider),
          SizedBox(height: h * 0.017),
          _TotalPaidRow(total: _fmtGhs(receipt.totalPaidPesewas), w: w),
          SizedBox(height: h * 0.019), // ~16dp
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.017),
          _PaymentStatusRow(
            method: receipt.paymentMethod,
            status: receipt.paymentStatus,
            w: w,
          ),
        ],
      ),
    );
  }
}

class _FareBreakdownHeader extends StatelessWidget {
  final String rideId;
  final double w;
  const _FareBreakdownHeader({required this.rideId, required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Fare Breakdown',
          style: TextStyle(
            fontSize: w * 0.036, // ~14dp
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        Text(
          'ID: #$rideId',
          style: TextStyle(
            fontSize: w * 0.031, // ~12dp
            fontWeight: FontWeight.w600,
            color: MyShopColors.primaryGold,
          ),
        ),
      ],
    );
  }
}

class _FareLineItem extends StatelessWidget {
  final String label;
  final String amount;
  final Color amountColor;
  final double w;

  const _FareLineItem({
    required this.label,
    required this.amount,
    required this.w,
    this.amountColor = MyShopColors.textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: w * 0.033, // ~13dp
            fontWeight: FontWeight.w400,
            color: MyShopColors.textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          amount,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w500,
            color: amountColor,
          ),
        ),
      ],
    );
  }
}

class _TotalPaidRow extends StatelessWidget {
  final String total;
  final double w;
  const _TotalPaidRow({required this.total, required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          'Total Paid',
          style: TextStyle(
            fontSize: w * 0.041, // ~16dp
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        const Spacer(),
        Text(
          total,
          style: TextStyle(
            fontSize: w * 0.051, // ~20dp
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _PaymentStatusRow extends StatelessWidget {
  final String method;
  final String status;
  final double w;
  const _PaymentStatusRow({
    required this.method,
    required this.status,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _MtnCircle(w: w),
        SizedBox(width: w * 0.026), // ~10dp
        Expanded(
          child: Text(
            method,
            style: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textPrimary,
            ),
          ),
        ),
        _PaymentBadge(status: status, w: w),
      ],
    );
  }
}

class _MtnCircle extends StatelessWidget {
  final double w;
  const _MtnCircle({required this.w});

  @override
  Widget build(BuildContext context) {
    final size = w * 0.082; // ~32dp
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: MyShopColors.mtnYellow,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        'M',
        style: TextStyle(
          fontSize: w * 0.033,
          fontWeight: FontWeight.w900,
          color: MyShopColors.textPrimary,
        ),
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  final String status;
  final double w;
  const _PaymentBadge({required this.status, required this.w});

  @override
  Widget build(BuildContext context) {
    final isSuccess = status == 'SUCCESS';
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.026, // ~10dp
        vertical: w * 0.010, // ~4dp
      ),
      decoration: BoxDecoration(
        color: isSuccess ? MyShopColors.successLight : MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(w * 0.010),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: w * 0.028, // ~11dp
          fontWeight: FontWeight.w700,
          color: isSuccess ? MyShopColors.success : MyShopColors.error,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ── Tip Section ───────────────────────────────────────────────────────────────

class _TipSection extends StatelessWidget {
  final RideReceipt receipt;
  final TipState tipState;
  final TextEditingController customController;
  final void Function(int pesewas) onPresetSelected;
  final void Function(String text) onCustomChanged;
  final VoidCallback? onConfirm;

  const _TipSection({
    required this.receipt,
    required this.tipState,
    required this.customController,
    required this.onPresetSelected,
    required this.onCustomChanged,
    required this.onConfirm,
  });

  static const _presets = [200, 500, 1000]; // GHS 2, 5, 10

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Container(
      color: MyShopColors.surfaceWhite,
      padding: EdgeInsets.all(w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add tip?',
            style: TextStyle(
              fontSize: w * 0.041,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          SizedBox(height: h * 0.017),
          Row(
            children: _presets
                .map(
                  (p) => Padding(
                    padding: EdgeInsets.only(right: w * 0.021),
                    child: _TipChip(
                      label: 'GHS ${(p / 100).toStringAsFixed(0)}',
                      isSelected: tipState.selectedPresetPesewas == p &&
                          tipState.customPesewas == 0,
                      onTap: () => onPresetSelected(p),
                      w: w,
                      h: h,
                    ),
                  ),
                )
                .toList(),
          ),
          SizedBox(height: h * 0.014),
          _CustomTipInput(
            controller: customController,
            onChanged: onCustomChanged,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.012),
          _TipDisclaimer(driverFirstName: receipt.driverFirstName, w: w),
          SizedBox(height: h * 0.019),
          _ConfirmTipButton(onPressed: onConfirm, w: w, h: h),
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double w;
  final double h;

  const _TipChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.051, // ~20dp
          vertical: h * 0.012, // ~10dp
        ),
        decoration: BoxDecoration(
          color:
              isSelected ? MyShopColors.primaryGold : MyShopColors.surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(
            color: isSelected ? MyShopColors.primaryGold : MyShopColors.divider,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : MyShopColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _CustomTipInput extends StatelessWidget {
  final TextEditingController controller;
  final void Function(String) onChanged;
  final double w;
  final double h;

  const _CustomTipInput({
    required this.controller,
    required this.onChanged,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: h * 0.057, // ~48dp
      decoration: BoxDecoration(
        border: Border.all(color: MyShopColors.divider),
        borderRadius: BorderRadius.circular(w * 0.021),
      ),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: w * 0.031),
            child: Text(
              'GHS',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
          Container(width: 1, color: MyShopColors.divider),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w500,
                color: MyShopColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Other amount',
                hintStyle: TextStyle(
                  fontSize: w * 0.033,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.disabled,
                ),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: w * 0.031),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TipDisclaimer extends StatelessWidget {
  final String driverFirstName;
  final double w;
  const _TipDisclaimer({required this.driverFirstName, required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: w * 0.036, // ~14dp
          color: MyShopColors.primaryGold,
        ),
        SizedBox(width: w * 0.015),
        Expanded(
          child: Text(
            '100% of tips go directly to $driverFirstName. Zero commission charged.',
            style: TextStyle(
              fontSize: w * 0.028, // ~11dp
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _ConfirmTipButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final double w;
  final double h;
  const _ConfirmTipButton({
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: h * 0.062, // ~52dp
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor:
              enabled ? MyShopColors.primaryGold : MyShopColors.surfaceGrey,
          foregroundColor: enabled ? Colors.white : MyShopColors.disabled,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(w * 0.021),
          ),
        ),
        child: Text(
          'CONFIRM TIP',
          style: TextStyle(
            fontSize: w * 0.036, // ~14dp
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.white : MyShopColors.disabled,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
