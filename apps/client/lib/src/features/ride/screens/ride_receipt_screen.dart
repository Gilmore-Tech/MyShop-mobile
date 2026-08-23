import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../providers/ride_receipt_provider.dart';
import '../utils/ride_receipt_pdf.dart';
import '../widgets/rate_ride_sheet.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 4.6 — serves two entry points:
//   • Right after ride completion + rating (fromCompletion = true): back → home
//   • Trip history "View Details" on activity list (fromCompletion = false):
//     back pops to the list.
// API: GET /v1/rides/:rideId  (EDD § Ride Module — completed ride endpoint)

class RideReceiptScreen extends ConsumerWidget {
  final String rideId;

  /// True when this receipt is shown immediately after a ride completes
  /// (post-rating). Back returns to home instead of popping.
  final bool fromCompletion;

  const RideReceiptScreen({
    super.key,
    required this.rideId,
    this.fromCompletion = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final receiptAsync = ref.watch(rideReceiptByIdProvider(rideId));

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: _appBar(context, w),
      body: receiptAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (_, __) => MyShopErrorBody(
          message: 'Could not load receipt',
          onRetry: () => ref.invalidate(rideReceiptByIdProvider(rideId)),
        ),
        data: (receipt) => _ReceiptBody(receipt: receipt, w: w, h: h),
      ),
      bottomNavigationBar: _ShareBar(rideId: rideId, w: w, h: h),
    );
  }

  AppBar _appBar(BuildContext context, double w) => AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        title: Text(
          'Ride Receipt',
          style: TextStyle(
            fontSize: w * 0.046, // ~18dp
            fontWeight: FontWeight.w600,
            color: MyShopColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: w * 0.021),
            child: IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: MyShopColors.textPrimary,
                size: w * 0.056, // ~22dp
              ),
              onPressed: () => _onBack(context),
            ),
          ),
        ],
      );

  void _onBack(BuildContext context) {
    // Post-completion flow: back takes the rider back to the home tab rather
    // than to the completion/rating screen underneath. From the trip history
    // flow we just pop back to the list.
    if (fromCompletion) {
      context.go(AppRoutes.home);
    } else {
      context.pop();
    }
  }
}

// ── Receipt Body ──────────────────────────────────────────────────────────────

class _ReceiptBody extends StatelessWidget {
  final RideReceiptData receipt;
  final double w;
  final double h;
  const _ReceiptBody({required this.receipt, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AmountHeader(totalDisplay: receipt.totalPaidDisplay, w: w, h: h),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          _ProviderCard(
            name: receipt.driverName,
            subtitle: receipt.vehicleDisplay,
            rating: receipt.driverRating,
            w: w,
            h: h,
          ),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          _RateProviderCTA(
            providerFirstName: receipt.driverName.split(RegExp(r'\s+')).first,
            providerKind: 'driver',
            onTap: () => showRateRideSheet(
              context,
              rideId: receipt.rideId,
              driverFirstName: receipt.driverName.split(RegExp(r'\s+')).first,
            ),
            w: w,
            h: h,
          ),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          _RouteSection(receipt: receipt, w: w, h: h),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          _RideBreakdownSection(receipt: receipt, w: w, h: h),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          _TransactionInfoRow(
            transactionId: receipt.rideId,
            dateTimeLabel: receipt.dateTimeLabel,
            w: w,
            h: h,
          ),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          _PaymentMethodSection(
            label: receipt.paymentMethodLabel,
            type: receipt.paymentMethodType,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.028),
        ],
      ),
    );
  }
}

// ── Amount Header ─────────────────────────────────────────────────────────────

class _AmountHeader extends StatelessWidget {
  final String totalDisplay;
  final double w;
  final double h;
  const _AmountHeader({
    required this.totalDisplay,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: h * 0.033), // ~28dp
      child: Column(
        children: [
          Text(
            'Total Paid',
            style: TextStyle(
              fontSize: w * 0.033, // ~13dp
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            totalDisplay,
            style: TextStyle(
              fontSize: w * 0.092, // ~36dp
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Provider Card ─────────────────────────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  final String name;
  final String subtitle;

  /// Null when the driver has no revealed ratings yet — renders "New"
  /// so the receipt is honest about a fresh provider rather than
  /// printing "0.0★".
  final double? rating;
  final double w;
  final double h;
  const _ProviderCard({
    required this.name,
    required this.subtitle,
    required this.rating,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    final avatarSize = w * 0.133; // ~52dp

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: w * 0.041, // ~16dp
        vertical: h * 0.017, // ~14dp
      ),
      padding: EdgeInsets.all(w * 0.036), // ~14dp
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.031), // ~12dp
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: avatarSize,
            height: avatarSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: MyShopColors.avatarPlaceholder,
            ),
            child: Icon(
              Icons.person_rounded,
              size: w * 0.072, // ~28dp
              color: MyShopColors.darkSlate,
            ),
          ),
          SizedBox(width: w * 0.036), // ~14dp
          // Name + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: w * 0.041, // ~16dp
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: w * 0.031, // ~12dp
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: w * 0.021),
          // Rating
          Row(
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
          ),
        ],
      ),
    );
  }
}

// ── Route Section ─────────────────────────────────────────────────────────────

class _RouteSection extends StatelessWidget {
  final RideReceiptData receipt;
  final double w;
  final double h;
  const _RouteSection(
      {required this.receipt, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final iconSize = w * 0.051; // ~20dp
    final connectorLeft = iconSize / 2 - 0.75;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041, // ~16dp
        vertical: h * 0.019, // ~16dp
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RouteRow(
            icon: Icons.radio_button_checked_rounded,
            iconColor: MyShopColors.textSecondary,
            label: 'PICKUP',
            address: receipt.pickupAddress,
            w: w,
          ),
          Padding(
            padding: EdgeInsets.only(left: connectorLeft),
            child: Container(
              width: 1.5,
              height: h * 0.028, // ~24dp
              color: MyShopColors.divider,
            ),
          ),
          _RouteRow(
            icon: Icons.location_on_rounded,
            iconColor: MyShopColors.primaryGold,
            label: 'DESTINATION',
            address: receipt.dropoffAddress,
            w: w,
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String address;
  final double w;
  const _RouteRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.address,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: w * 0.051, color: iconColor),
        SizedBox(width: w * 0.031), // ~12dp
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: w * 0.026, // ~10dp
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.4,
                ),
              ),
              SizedBox(height: w * 0.005),
              Text(
                address,
                style: TextStyle(
                  fontSize: w * 0.036, // ~14dp
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

// ── Ride Breakdown ────────────────────────────────────────────────────────────

class _RideBreakdownSection extends StatelessWidget {
  final RideReceiptData receipt;
  final double w;
  final double h;
  const _RideBreakdownSection({
    required this.receipt,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041, // ~16dp
        vertical: h * 0.019, // ~16dp
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAYMENT BREAKDOWN',
            style: TextStyle(
              fontSize: w * 0.026, // ~10dp
              fontWeight: FontWeight.w900,
              color: MyShopColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          SizedBox(height: h * 0.017),
          _LineItem(
            label: 'Base Fare',
            amount: receipt.baseFareDisplay,
            w: w,
          ),
          SizedBox(height: h * 0.012),
          _LineItem(
            label: 'Distance (${receipt.distanceKm.toStringAsFixed(1)} km)',
            amount: receipt.distanceFareDisplay,
            w: w,
          ),
          SizedBox(height: h * 0.012),
          _LineItem(
            label: 'Booking Fee',
            amount: receipt.bookingFeeDisplay,
            w: w,
          ),
          SizedBox(height: h * 0.012),
          _LineItem(
            label: 'Taxes & Levies',
            amount: receipt.taxesDisplay,
            w: w,
          ),
          if ((receipt.toll?.amountPesewas ?? 0) > 0) ...[
            SizedBox(height: h * 0.012),
            _LineItem(
              label: receipt.toll!.label,
              amount: receipt.tollDisplay,
              w: w,
            ),
          ],
          if (receipt.promoDiscountPesewas > 0) ...[
            SizedBox(height: h * 0.012),
            _LineItem(
              label: 'Promotional Discount',
              amount: receipt.promoDiscountDisplay,
              amountColor: MyShopColors.error,
              w: w,
            ),
          ],
          if (receipt.loyaltyDiscountPesewas > 0) ...[
            SizedBox(height: h * 0.012),
            _LineItem(
              label: 'Loyalty Discount',
              amount: receipt.loyaltyDiscountDisplay,
              amountColor: MyShopColors.error,
              w: w,
            ),
          ],
          SizedBox(height: h * 0.019),
          const Divider(height: 2, thickness: 2, color: MyShopColors.divider),
          SizedBox(height: h * 0.019),
          Row(
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
                receipt.totalPaidDisplay,
                style: TextStyle(
                  fontSize: w * 0.041, // ~16dp
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Line Item ─────────────────────────────────────────────────────────────────

class _LineItem extends StatelessWidget {
  final String label;
  final String amount;
  final Color? amountColor;
  final double w;
  const _LineItem({
    required this.label,
    required this.amount,
    this.amountColor,
    required this.w,
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
            color: amountColor ?? MyShopColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Transaction Info ──────────────────────────────────────────────────────────

class _TransactionInfoRow extends StatelessWidget {
  final String transactionId;
  final String dateTimeLabel;
  final double w;
  final double h;
  const _TransactionInfoRow({
    required this.transactionId,
    required this.dateTimeLabel,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.019,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TRANSACTION ID',
                  style: TextStyle(
                    fontSize: w * 0.026,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textSecondary,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: h * 0.007),
                Text(
                  transactionId,
                  style: TextStyle(
                    fontSize: w * 0.033, // ~13dp
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: w * 0.021),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'DATE & TIME',
                  style: TextStyle(
                    fontSize: w * 0.026,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textSecondary,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: h * 0.007),
                Text(
                  dateTimeLabel,
                  style: TextStyle(
                    fontSize: w * 0.031, // ~12dp
                    fontWeight: FontWeight.w400,
                    color: MyShopColors.textPrimary,
                  ),
                  textAlign: TextAlign.end,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Payment Method ────────────────────────────────────────────────────────────

class _PaymentMethodSection extends StatelessWidget {
  final String label;
  final PaymentMethodType type;
  final double w;
  final double h;
  const _PaymentMethodSection({
    required this.label,
    required this.type,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,
        vertical: h * 0.019,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAYMENT METHOD',
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          SizedBox(height: h * 0.014),
          Row(
            children: [
              _PaymentIcon(type: type, w: w),
              SizedBox(width: w * 0.031),
              Text(
                label,
                style: TextStyle(
                  fontSize: w * 0.036, // ~14dp
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentIcon extends StatelessWidget {
  final PaymentMethodType type;
  final double w;
  const _PaymentIcon({required this.type, required this.w});

  @override
  Widget build(BuildContext context) {
    final circleSize = w * 0.082; // ~32dp

    return switch (type) {
      PaymentMethodType.mtn => Container(
          width: circleSize,
          height: circleSize,
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
        ),
      PaymentMethodType.vodafone => Container(
          width: circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: Color(0xFFE60000),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'V',
            style: TextStyle(
              fontSize: w * 0.033,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      PaymentMethodType.airtelTigo => Container(
          width: circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: Color(0xFFEE1C25),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'AT',
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      PaymentMethodType.visa => Container(
          width: circleSize * 1.4,
          height: circleSize,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F71),
            borderRadius: BorderRadius.circular(w * 0.010),
          ),
          alignment: Alignment.center,
          child: Text(
            'VISA',
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ),
      PaymentMethodType.mastercard => Container(
          width: circleSize * 1.4,
          height: circleSize,
          decoration: BoxDecoration(
            color: const Color(0xFFEB001B),
            borderRadius: BorderRadius.circular(w * 0.010),
          ),
          alignment: Alignment.center,
          child: Text(
            'MC',
            style: TextStyle(
              fontSize: w * 0.026,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
      PaymentMethodType.cash => Container(
          width: circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: MyShopColors.success,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.attach_money_rounded,
            size: w * 0.041,
            color: Colors.white,
          ),
        ),
    };
  }
}

// ── Share Bar ─────────────────────────────────────────────────────────────────

class _ShareBar extends ConsumerStatefulWidget {
  final String rideId;
  final double w;
  final double h;
  const _ShareBar({required this.rideId, required this.w, required this.h});

  @override
  ConsumerState<_ShareBar> createState() => _ShareBarState();
}

class _ShareBarState extends ConsumerState<_ShareBar> {
  bool _generating = false;

  /// Builds the PDF receipt and opens the OS share sheet so the rider can
  /// share it (WhatsApp, Email, Drive, …) or save it via "Save to Files" /
  /// "Save to Phone". A single tap covers both flows.
  Future<void> _onShare(RideReceiptData receipt) async {
    if (_generating) return;
    setState(() => _generating = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await buildRideReceiptPdf(receipt);
      if (!mounted) return;

      // Anchor the share sheet to this bar's rect — required for the popover
      // on iPad and harmless on phones.
      final box = context.findRenderObject() as RenderBox?;
      final bounds = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'MyShop-Receipt-${receipt.rideId.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}.pdf',
        bounds: bounds,
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text("Couldn't generate the receipt. Please try again."),
        ),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final h = widget.h;
    final receiptAsync = ref.watch(rideReceiptByIdProvider(widget.rideId));
    final receipt = receiptAsync.valueOrNull;
    // Disabled until the receipt has loaded — there's nothing to share yet.
    final enabled = receipt != null && !_generating;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: h * 0.076, // ~64dp
        child: Material(
          color: enabled
              ? MyShopColors.primaryGold
              : MyShopColors.primaryGold.withValues(alpha: 0.5),
          child: InkWell(
            onTap: enabled ? () => _onShare(receipt) : null,
            child: Center(
              child: _generating
                  ? SizedBox(
                      width: w * 0.051,
                      height: w * 0.051,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                          size: w * 0.051, // ~20dp
                        ),
                        SizedBox(width: w * 0.021),
                        Text(
                          'SHARE RECEIPT',
                          style: TextStyle(
                            fontSize: w * 0.036, // ~14dp
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Loading Skeleton ──────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  final double w;
  final double h;
  const _LoadingSkeleton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Amount area
          Padding(
            padding: EdgeInsets.symmetric(vertical: h * 0.033),
            child: Column(
              children: [
                _SkeletonBox(width: w * 0.200, height: h * 0.017, w: w),
                SizedBox(height: h * 0.009),
                _SkeletonBox(width: w * 0.460, height: h * 0.052, w: w),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          // Provider card
          Container(
            margin: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical: h * 0.017,
            ),
            padding: EdgeInsets.all(w * 0.036),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(w * 0.031),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Row(
              children: [
                _SkeletonCircle(size: w * 0.133, w: w),
                SizedBox(width: w * 0.036),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBox(width: w * 0.300, height: h * 0.019, w: w),
                      SizedBox(height: h * 0.007),
                      _SkeletonBox(width: w * 0.500, height: h * 0.014, w: w),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          // Route
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical: h * 0.019,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: w * 0.560, height: h * 0.021, w: w),
                SizedBox(height: h * 0.014),
                _SkeletonBox(width: w * 0.660, height: h * 0.021, w: w),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: MyShopColors.divider),
          // Breakdown
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical: h * 0.019,
            ),
            child: Column(
              children: List.generate(
                  4,
                  (i) => Padding(
                        padding: EdgeInsets.only(bottom: h * 0.012),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _SkeletonBox(
                                width: w * 0.350, height: h * 0.017, w: w),
                            _SkeletonBox(
                                width: w * 0.200, height: h * 0.017, w: w),
                          ],
                        ),
                      )),
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double w;
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(w * 0.010),
      ),
    );
  }
}

class _SkeletonCircle extends StatelessWidget {
  final double size;
  final double w;
  const _SkeletonCircle({required this.size, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: MyShopColors.divider,
        shape: BoxShape.circle,
      ),
    );
  }
}

// ── Rate Provider CTA ─────────────────────────────────────────────────────────
//
// Inline section between the provider card and ride/service details. Lets
// the client open the rating sheet from the receipt — useful when they
// skipped rating on the post-completion screen, or are revisiting a
// historical receipt from the activity list.

class _RateProviderCTA extends StatelessWidget {
  final String providerFirstName;
  final String providerKind; // 'driver' | 'artisan'
  final VoidCallback onTap;
  final double w, h;

  const _RateProviderCTA({
    required this.providerFirstName,
    required this.providerKind,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.022,
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.108,
              height: w * 0.108,
              decoration: BoxDecoration(
                color: MyShopColors.primaryGoldLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: MyShopColors.primaryGold.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(
                Icons.star_rounded,
                size: w * 0.056,
                color: MyShopColors.primaryGold,
              ),
            ),
            SizedBox(width: w * 0.031),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rate $providerFirstName',
                    style: TextStyle(
                      fontSize: w * 0.041,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: h * 0.003),
                  Text(
                    'Share your feedback for this $providerKind',
                    style: TextStyle(
                      fontSize: w * 0.031,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: w * 0.056,
              color: MyShopColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
