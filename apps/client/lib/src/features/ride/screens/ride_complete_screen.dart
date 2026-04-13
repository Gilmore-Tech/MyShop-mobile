import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/ride_provider.dart';
import '../widgets/rate_ride_sheet.dart';

// ── Design Tokens ──────────────────────────────────────────────────────────────
const _offWhite = Color(0xFFF6F7F8);
const _surfaceWhite = Color(0xFFFFFFFF);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold = Color(0xFFF5A623);
const _success = Color(0xFF27AE60);
const _successLight = Color(0xFFE8F8EF);
const _error = Color(0xFFEB5757);
const _divider = Color(0xFFE0E0E0);
const _darkSlate = Color(0xFF46535D);
const _surfaceGrey = Color(0xFFF3F5F6);
const _disabled = Color(0xFFBDBDBD);
const _avatarBg = Color(0xFFE0E6FF);

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

  @override
  void initState() {
    super.initState();
    // Show rating sheet automatically once the first frame is rendered.
    // PRD 4.3 — driver marks ride complete → client rates driver.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showRateRideSheet(context, ref.read(rideReceiptProvider));
      }
    });
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
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Scaffold(
      backgroundColor: _offWhite,
      body: SafeArea(
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
                        ref.read(tipStateProvider.notifier).selectPreset(pesewas);
                      },
                      onCustomChanged: (text) =>
                          ref.read(tipStateProvider.notifier).setCustom(text),
                      onConfirm: tipState.hasAmount
                          ? () => _submitTip(context, receipt, tipState)
                          : null,
                    ),
                    SizedBox(height: h * 0.028), // ~24dp
                  ],
                ),
              ),
            ),
            _BottomNav(w: w, h: h),
          ],
        ),
      ),
    );
  }

  void _submitTip(BuildContext context, RideReceipt receipt, TipState tip) {
    // TODO: POST /v1/payments/:id/tip — wire up once API client is available
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Tip of ${_fmtGhs(tip.effectivePesewas)} sent to ${receipt.driverFirstName}!',
        ),
        backgroundColor: _success,
        behavior: SnackBarBehavior.floating,
      ),
    );
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
      color: _surfaceWhite,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.021, // ~8dp
        vertical: h * 0.012,   // ~10dp
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: w * 0.021,
                vertical: h * 0.012,
              ),
              child: Icon(
                Icons.arrow_back,
                color: _textPrimary,
                size: w * 0.056, // ~22dp
              ),
            ),
          ),
          SizedBox(width: w * 0.010), // ~4dp
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Arrived Safe',
                style: TextStyle(
                  fontSize: w * 0.051, // ~20dp
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              Text(
                receipt.completedAt,
                style: TextStyle(
                  fontSize: w * 0.031, // ~12dp
                  fontWeight: FontWeight.w400,
                  color: _textSecondary,
                ),
              ),
            ],
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
      color: _surfaceWhite,
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
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: w * 0.008), // ~3dp
                Text(
                  receipt.vehicleDisplay,
                  style: TextStyle(
                    fontSize: w * 0.031, // ~12dp
                    fontWeight: FontWeight.w400,
                    color: _textSecondary,
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
        color: _avatarBg,
        border: Border.all(color: _gold, width: w * 0.005), // ~2dp
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
        color: _darkSlate,
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
        vertical: w * 0.010,   // ~4dp
      ),
      decoration: BoxDecoration(
        color: _successLight,
        borderRadius: BorderRadius.circular(w * 0.051), // ~20dp
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: w * 0.031, // ~12dp
            color: _success,
          ),
          SizedBox(width: w * 0.010),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: w * 0.028, // ~11dp
              fontWeight: FontWeight.w600,
              color: _success,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  final double rating;
  final double w;
  const _RatingPill({required this.rating, required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: w * 0.041, color: _gold), // ~16dp
        SizedBox(width: w * 0.008),
        Text(
          rating.toStringAsFixed(1),
          style: TextStyle(
            fontSize: w * 0.036, // ~14dp
            fontWeight: FontWeight.w700,
            color: _textPrimary,
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
      color: _surfaceWhite,
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041, // ~16dp
        vertical: h * 0.017,   // ~14dp
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RouteStop(
            icon: Icons.radio_button_checked,
            iconColor: _textSecondary,
            typeLabel: 'PICKUP',
            address: receipt.pickupAddress,
            w: w,
          ),
          Padding(
            padding: EdgeInsets.only(left: connectorLeft),
            child: Container(
              width: 1.5,
              height: h * 0.019, // ~16dp
              color: _divider,
            ),
          ),
          _RouteStop(
            icon: Icons.location_on_rounded,
            iconColor: _gold,
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
        SizedBox(width: w * 0.031),                    // ~12dp
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: w * 0.026, // ~10dp
                  fontWeight: FontWeight.w700,
                  color: _textSecondary,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(height: w * 0.005),
              Text(
                address,
                style: TextStyle(
                  fontSize: w * 0.033, // ~13dp
                  fontWeight: FontWeight.w500,
                  color: _textPrimary,
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
      color: _surfaceWhite,
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
          const Divider(height: 1, thickness: 1, color: _divider),
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
          SizedBox(height: h * 0.012),
          _FareLineItem(
            label: 'Promotional Discount',
            amount: '- ${_fmtGhs(receipt.promoDiscountPesewas)}',
            amountColor: _error,
            w: w,
          ),
          SizedBox(height: h * 0.017),
          const Divider(height: 2, thickness: 2, color: _divider),
          SizedBox(height: h * 0.017),
          _TotalPaidRow(total: _fmtGhs(receipt.totalPaidPesewas), w: w),
          SizedBox(height: h * 0.019), // ~16dp
          const Divider(height: 1, thickness: 1, color: _divider),
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
            color: _textPrimary,
          ),
        ),
        Text(
          'ID: #$rideId',
          style: TextStyle(
            fontSize: w * 0.031, // ~12dp
            fontWeight: FontWeight.w600,
            color: _gold,
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
    this.amountColor = _textPrimary,
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
            color: _textSecondary,
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
            color: _textPrimary,
          ),
        ),
        const Spacer(),
        Text(
          total,
          style: TextStyle(
            fontSize: w * 0.051, // ~20dp
            fontWeight: FontWeight.w700,
            color: _textPrimary,
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
              color: _textPrimary,
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
        color: Color(0xFFFFCC00),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        'M',
        style: TextStyle(
          fontSize: w * 0.033,
          fontWeight: FontWeight.w900,
          color: _textPrimary,
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
        vertical: w * 0.010,   // ~4dp
      ),
      decoration: BoxDecoration(
        color: isSuccess ? _successLight : const Color(0xFFFDE8E8),
        borderRadius: BorderRadius.circular(w * 0.010),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontSize: w * 0.028, // ~11dp
          fontWeight: FontWeight.w700,
          color: isSuccess ? _success : _error,
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
      color: _surfaceWhite,
      padding: EdgeInsets.all(w * 0.041),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add tip?',
            style: TextStyle(
              fontSize: w * 0.041,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
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
          vertical: h * 0.012,   // ~10dp
        ),
        decoration: BoxDecoration(
          color: isSelected ? _gold : _surfaceGrey,
          borderRadius: BorderRadius.circular(w * 0.021),
          border: Border.all(
            color: isSelected ? _gold : _divider,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: w * 0.033,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : _textPrimary,
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
        border: Border.all(color: _divider),
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
                color: _textSecondary,
              ),
            ),
          ),
          Container(width: 1, color: _divider),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w500,
                color: _textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Other amount',
                hintStyle: TextStyle(
                  fontSize: w * 0.033,
                  fontWeight: FontWeight.w400,
                  color: _disabled,
                ),
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: w * 0.031),
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
          color: _gold,
        ),
        SizedBox(width: w * 0.015),
        Expanded(
          child: Text(
            '100% of tips go directly to $driverFirstName. Zero commission charged.',
            style: TextStyle(
              fontSize: w * 0.028, // ~11dp
              fontWeight: FontWeight.w400,
              color: _textSecondary,
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
          backgroundColor: enabled ? _gold : _surfaceGrey,
          foregroundColor: enabled ? Colors.white : _disabled,
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
            color: enabled ? Colors.white : _disabled,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── Bottom Navigation ─────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final double w;
  final double h;
  const _BottomNav({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: w * 0.026,
            offset: Offset(0, -(w * 0.005)),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: h * 0.071, // ~60dp
          child: Row(
            children: [
              _NavItem(
                icon: Icons.location_on_rounded,
                label: 'Home',
                isActive: true,
                onTap: () =>
                    Navigator.of(context).popUntil((r) => r.isFirst),
                w: w,
              ),
              _NavItem(
                icon: Icons.access_time_rounded,
                label: 'Activity',
                isActive: false,
                onTap: () {},
                w: w,
              ),
              _NavItem(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet',
                isActive: false,
                onTap: () {},
                w: w,
              ),
              _NavItem(
                icon: Icons.person_outline_rounded,
                label: 'Account',
                isActive: false,
                onTap: () {},
                w: w,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final double w;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? _gold : _darkSlate;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: w * 0.056), // ~22dp
            SizedBox(height: w * 0.008),
            Text(
              label,
              style: TextStyle(
                fontSize: w * 0.026, // ~10dp
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
