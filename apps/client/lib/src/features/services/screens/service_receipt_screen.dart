import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ride/providers/ride_receipt_provider.dart' show PaymentMethodType;
import '../providers/service_receipt_provider.dart';

// ── Design Tokens ─────────────────────────────────────────────────────────────
const _surfaceWhite  = Color(0xFFFFFFFF);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _textHint      = Color(0xFFBDBDBD);
const _gold          = Color(0xFFF5A623);
const _darkSlate     = Color(0xFF46535D);
const _divider       = Color(0xFFE0E0E0);
const _avatarBg      = Color(0xFFE0E6FF);
const _mtnYellow     = Color(0xFFFFCC00);

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 4.6 — opened from activity list "View Details" on a job transaction.
// API: GET /v1/jobs/:jobId  (EDD § Job Module — completed job endpoint)

class ServiceReceiptScreen extends ConsumerWidget {
  final String jobId;
  const ServiceReceiptScreen({super.key, required this.jobId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size         = MediaQuery.sizeOf(context);
    final w            = size.width;
    final h            = size.height;
    final receiptAsync = ref.watch(serviceReceiptByIdProvider(jobId));

    return Scaffold(
      backgroundColor: _surfaceWhite,
      appBar: _appBar(context, w),
      body: receiptAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error:   (_, __) => _ErrorBody(
          w: w, h: h,
          onRetry: () => ref.invalidate(serviceReceiptByIdProvider(jobId)),
        ),
        data: (receipt) => _ReceiptBody(receipt: receipt, w: w, h: h),
      ),
      bottomNavigationBar: _ShareBar(w: w, h: h),
    );
  }

  AppBar _appBar(BuildContext context, double w) => AppBar(
        backgroundColor: _surfaceWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        title: Text(
          'Service Receipt',
          style: TextStyle(
            fontSize:   w * 0.046,   // ~18dp
            fontWeight: FontWeight.w600,
            color:      _textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: EdgeInsets.only(right: w * 0.021),
            child: IconButton(
              icon: Icon(
                Icons.close_rounded,
                color: _textPrimary,
                size:  w * 0.056,   // ~22dp
              ),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      );
}

// ── Receipt Body ──────────────────────────────────────────────────────────────

class _ReceiptBody extends StatelessWidget {
  final ServiceReceiptData receipt;
  final double             w;
  final double             h;
  const _ReceiptBody({required this.receipt, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _AmountHeader(totalDisplay: receipt.totalPaidDisplay, w: w, h: h),
          const Divider(height: 1, thickness: 1, color: _divider),
          _ProviderCard(
            name:     receipt.artisanName,
            subtitle: receipt.artisanSpecialty,
            rating:   receipt.artisanRating,
            w: w,
            h: h,
          ),
          const Divider(height: 1, thickness: 1, color: _divider),
          _ServiceDetailsSection(receipt: receipt, w: w, h: h),
          const Divider(height: 1, thickness: 1, color: _divider),
          _ServiceBreakdownSection(receipt: receipt, w: w, h: h),
          const Divider(height: 1, thickness: 1, color: _divider),
          _TransactionInfoRow(
            transactionId: receipt.jobId,
            dateTimeLabel: receipt.dateTimeLabel,
            w: w,
            h: h,
          ),
          const Divider(height: 1, thickness: 1, color: _divider),
          _PaymentMethodSection(
            label: receipt.paymentMethodLabel,
            type:  receipt.paymentMethodType,
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
      padding: EdgeInsets.symmetric(vertical: h * 0.033),   // ~28dp
      child: Column(
        children: [
          Text(
            'Total Paid',
            style: TextStyle(
              fontSize:   w * 0.033,   // ~13dp
              fontWeight: FontWeight.w400,
              color:      _textSecondary,
            ),
          ),
          SizedBox(height: h * 0.007),
          Text(
            totalDisplay,
            style: TextStyle(
              fontSize:   w * 0.092,   // ~36dp
              fontWeight: FontWeight.w700,
              color:      _textPrimary,
              height:     1.1,
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
  final double rating;
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
    final avatarSize = w * 0.133;   // ~52dp

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: w * 0.041,   // ~16dp
        vertical:   h * 0.017,   // ~14dp
      ),
      padding: EdgeInsets.all(w * 0.036),   // ~14dp
      decoration: BoxDecoration(
        color:        _surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.031),   // ~12dp
        border:       Border.all(color: _divider),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width:  avatarSize,
            height: avatarSize,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _avatarBg,
            ),
            child: Icon(
              Icons.person_rounded,
              size:  w * 0.072,   // ~28dp
              color: _darkSlate,
            ),
          ),
          SizedBox(width: w * 0.036),   // ~14dp
          // Name + subtitle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize:   w * 0.041,   // ~16dp
                    fontWeight: FontWeight.w700,
                    color:      _textPrimary,
                  ),
                ),
                SizedBox(height: h * 0.005),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize:   w * 0.031,   // ~12dp
                    fontWeight: FontWeight.w400,
                    color:      _textSecondary,
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
              Icon(Icons.star_rounded, size: w * 0.041, color: _gold),
              SizedBox(width: w * 0.008),
              Text(
                rating.toStringAsFixed(1),
                style: TextStyle(
                  fontSize:   w * 0.036,   // ~14dp
                  fontWeight: FontWeight.w700,
                  color:      _textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Service Details Section ───────────────────────────────────────────────────
// Shows service location and work duration — replaces the pickup/destination
// route section used in ride receipts.

class _ServiceDetailsSection extends StatelessWidget {
  final ServiceReceiptData receipt;
  final double             w;
  final double             h;
  const _ServiceDetailsSection({
    required this.receipt,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,   // ~16dp
        vertical:   h * 0.019,   // ~16dp
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(
            icon:    Icons.location_on_rounded,
            label:   'SERVICE LOCATION',
            value:   receipt.serviceLocation,
            w: w,
            h: h,
          ),
          SizedBox(height: h * 0.017),   // ~14dp
          _DetailRow(
            icon:    Icons.access_time_rounded,
            label:   'WORK DURATION',
            value:   receipt.workDurationLabel,
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final double   w;
  final double   h;
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: w * 0.051, color: _gold),   // ~20dp
        SizedBox(width: w * 0.031),                   // ~12dp
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize:    w * 0.026,   // ~10dp
                  fontWeight:  FontWeight.w900,
                  color:       _textSecondary,
                  letterSpacing: 1.4,
                ),
              ),
              SizedBox(height: w * 0.005),
              Text(
                value,
                style: TextStyle(
                  fontSize:   w * 0.036,   // ~14dp
                  fontWeight: FontWeight.w500,
                  color:      _textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Service Breakdown ─────────────────────────────────────────────────────────

class _ServiceBreakdownSection extends StatelessWidget {
  final ServiceReceiptData receipt;
  final double             w;
  final double             h;
  const _ServiceBreakdownSection({
    required this.receipt,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.041,   // ~16dp
        vertical:   h * 0.019,   // ~16dp
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAYMENT BREAKDOWN',
            style: TextStyle(
              fontSize:    w * 0.026,   // ~10dp
              fontWeight:  FontWeight.w900,
              color:       _textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          SizedBox(height: h * 0.017),
          _LineItem(
            label:  'Service Call Fee',
            amount: receipt.serviceCallFeeDisplay,
            w: w,
          ),
          SizedBox(height: h * 0.012),
          _LineItem(
            label:  'Labor (${receipt.laborHoursLabel})',
            amount: receipt.laborDisplay,
            w: w,
          ),
          SizedBox(height: h * 0.012),
          _LineItem(
            label:  'Materials',
            amount: receipt.materialsDisplay,
            w: w,
          ),
          SizedBox(height: h * 0.019),
          const Divider(height: 2, thickness: 2, color: _divider),
          SizedBox(height: h * 0.019),
          Row(
            children: [
              Text(
                'Total Paid',
                style: TextStyle(
                  fontSize:   w * 0.041,   // ~16dp
                  fontWeight: FontWeight.w700,
                  color:      _textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                receipt.totalPaidDisplay,
                style: TextStyle(
                  fontSize:   w * 0.041,   // ~16dp
                  fontWeight: FontWeight.w700,
                  color:      _textPrimary,
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
  final double w;
  const _LineItem({required this.label, required this.amount, required this.w});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize:   w * 0.033,   // ~13dp
            fontWeight: FontWeight.w400,
            color:      _textSecondary,
          ),
        ),
        const Spacer(),
        Text(
          amount,
          style: TextStyle(
            fontSize:   w * 0.033,
            fontWeight: FontWeight.w500,
            color:      _textPrimary,
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
        vertical:   h * 0.019,
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
                    fontSize:    w * 0.026,
                    fontWeight:  FontWeight.w900,
                    color:       _textSecondary,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: h * 0.007),
                Text(
                  transactionId,
                  style: TextStyle(
                    fontSize:   w * 0.033,   // ~13dp
                    fontWeight: FontWeight.w600,
                    color:      _textPrimary,
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
                    fontSize:    w * 0.026,
                    fontWeight:  FontWeight.w900,
                    color:       _textSecondary,
                    letterSpacing: 1.4,
                  ),
                ),
                SizedBox(height: h * 0.007),
                Text(
                  dateTimeLabel,
                  style: TextStyle(
                    fontSize:   w * 0.031,   // ~12dp
                    fontWeight: FontWeight.w400,
                    color:      _textPrimary,
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
  final String            label;
  final PaymentMethodType type;
  final double            w;
  final double            h;
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
        vertical:   h * 0.019,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PAYMENT METHOD',
            style: TextStyle(
              fontSize:    w * 0.026,
              fontWeight:  FontWeight.w900,
              color:       _textSecondary,
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
                  fontSize:   w * 0.036,   // ~14dp
                  fontWeight: FontWeight.w600,
                  color:      _textPrimary,
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
  final double            w;
  const _PaymentIcon({required this.type, required this.w});

  @override
  Widget build(BuildContext context) {
    final circleSize = w * 0.082;   // ~32dp

    return switch (type) {
      PaymentMethodType.mtn => Container(
          width:  circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: _mtnYellow,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'M',
            style: TextStyle(
              fontSize:   w * 0.033,
              fontWeight: FontWeight.w900,
              color:      _textPrimary,
            ),
          ),
        ),
      PaymentMethodType.vodafone => Container(
          width:  circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: Color(0xFFE60000),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'V',
            style: TextStyle(
              fontSize:   w * 0.033,
              fontWeight: FontWeight.w900,
              color:      Colors.white,
            ),
          ),
        ),
      PaymentMethodType.airtelTigo => Container(
          width:  circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: Color(0xFFEE1C25),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            'AT',
            style: TextStyle(
              fontSize:   w * 0.026,
              fontWeight: FontWeight.w900,
              color:      Colors.white,
            ),
          ),
        ),
      PaymentMethodType.visa => Container(
          width:  circleSize * 1.4,
          height: circleSize,
          decoration: BoxDecoration(
            color:        const Color(0xFF1A1F71),
            borderRadius: BorderRadius.circular(w * 0.010),
          ),
          alignment: Alignment.center,
          child: Text(
            'VISA',
            style: TextStyle(
              fontSize:    w * 0.026,
              fontWeight:  FontWeight.w900,
              color:       Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ),
      PaymentMethodType.mastercard => Container(
          width:  circleSize * 1.4,
          height: circleSize,
          decoration: BoxDecoration(
            color:        const Color(0xFFEB001B),
            borderRadius: BorderRadius.circular(w * 0.010),
          ),
          alignment: Alignment.center,
          child: Text(
            'MC',
            style: TextStyle(
              fontSize:   w * 0.026,
              fontWeight: FontWeight.w900,
              color:      Colors.white,
            ),
          ),
        ),
      PaymentMethodType.cash => Container(
          width:  circleSize,
          height: circleSize,
          decoration: const BoxDecoration(
            color: Color(0xFF27AE60),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.attach_money_rounded,
            size:  w * 0.041,
            color: Colors.white,
          ),
        ),
    };
  }
}

// ── Share Bar ─────────────────────────────────────────────────────────────────

class _ShareBar extends StatelessWidget {
  final double w;
  final double h;
  const _ShareBar({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: h * 0.076,   // ~64dp
        child: Material(
          color: _gold,
          child: InkWell(
            onTap: () {
              // TODO: share_plus — Share.share(receiptText)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Receipt sharing coming soon.')),
              );
            },
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.share_rounded,
                    color: Colors.white,
                    size:  w * 0.051,   // ~20dp
                  ),
                  SizedBox(width: w * 0.021),
                  Text(
                    'SHARE RECEIPT',
                    style: TextStyle(
                      fontSize:    w * 0.036,   // ~14dp
                      fontWeight:  FontWeight.w700,
                      color:       Colors.white,
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
          const Divider(height: 1, thickness: 1, color: _divider),
          // Provider card
          Container(
            margin: EdgeInsets.symmetric(
              horizontal: w * 0.041, vertical: h * 0.017,
            ),
            padding: EdgeInsets.all(w * 0.036),
            decoration: BoxDecoration(
              color:        _surfaceGrey,
              borderRadius: BorderRadius.circular(w * 0.031),
              border:       Border.all(color: _divider),
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
          const Divider(height: 1, thickness: 1, color: _divider),
          // Service details
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041, vertical: h * 0.019,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonBox(width: w * 0.620, height: h * 0.021, w: w),
                SizedBox(height: h * 0.017),
                _SkeletonBox(width: w * 0.250, height: h * 0.021, w: w),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: _divider),
          // Breakdown
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041, vertical: h * 0.019,
            ),
            child: Column(
              children: List.generate(3, (i) => Padding(
                padding: EdgeInsets.only(bottom: h * 0.012),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _SkeletonBox(width: w * 0.350, height: h * 0.017, w: w),
                    _SkeletonBox(width: w * 0.200, height: h * 0.017, w: w),
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
      width:  width,
      height: height,
      decoration: BoxDecoration(
        color:        const Color(0xFFE0E0E0),
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
      width:  size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFE0E0E0),
        shape: BoxShape.circle,
      ),
    );
  }
}

// ── Error Body ────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final double       w;
  final double       h;
  final VoidCallback onRetry;
  const _ErrorBody({required this.w, required this.h, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size:  w * 0.154,   // ~60dp
              color: _textHint,
            ),
            SizedBox(height: h * 0.019),
            Text(
              'Could not load receipt',
              style: TextStyle(
                fontSize:   w * 0.046,
                fontWeight: FontWeight.w700,
                color:      _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.009),
            Text(
              'Please check your connection and try again.',
              style: TextStyle(
                fontSize:   w * 0.033,
                fontWeight: FontWeight.w400,
                color:      _textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.028),
            SizedBox(
              width:  double.infinity,
              height: h * 0.062,   // ~52dp
              child: OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  side:  const BorderSide(color: _gold),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(w * 0.021),
                  ),
                ),
                child: Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize:   w * 0.036,
                    fontWeight: FontWeight.w600,
                    color:      _gold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
