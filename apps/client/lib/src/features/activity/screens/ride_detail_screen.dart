import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _bg            = Color(0xFFF6F7F8);
const _surfaceWhite  = Color(0xFFFFFFFF);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _gold          = Color(0xFFF5A623);
const _success       = Color(0xFF27AE60);
const _successLight  = Color(0xFFE8F8EE);
const _danger        = Color(0xFFEB5757);
const _divider       = Color(0xFFE8EAEC);

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.9 — Historical ride detail; client can view receipt or raise a dispute.
// EDD: GET /v1/rides/:id

class RideDetailScreen extends ConsumerWidget {
  const RideDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size   = MediaQuery.sizeOf(context);
    final w      = size.width;
    final h      = size.height;
    final bot    = MediaQuery.paddingOf(context).bottom;
    final rideId = GoRouterState.of(context).pathParameters['rideId'] ?? 'RIDE-2041';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Ride Detail',
            style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: () =>
                context.push(AppRoutes.rideReceiptPath(rideId)),
            child: Text('Receipt',
                style: TextStyle(
                    color:      _gold,
                    fontSize:   w * 0.036,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(w * 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusCard(w: w, h: h),
            SizedBox(height: h * 0.020),
            _RouteCard(w: w, h: h),
            SizedBox(height: h * 0.020),
            _DriverCard(w: w, h: h),
            SizedBox(height: h * 0.020),
            _FareCard(w: w, h: h),
            SizedBox(height: h * 0.024),
            _ActionRow(
              rideId: rideId,
              w: w, h: h, bot: bot,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Status card ────────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final double w, h;
  const _StatusCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color:      Colors.black.withAlpha(8),
              blurRadius: 8,
              offset:     const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(w * 0.032),
            decoration: const BoxDecoration(
                color: _successLight, shape: BoxShape.circle),
            child: const Icon(Icons.directions_car_rounded,
                color: _success, size: 24),
          ),
          SizedBox(width: w * 0.036),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Work Shuttle (Corporate)',
                    style: TextStyle(
                      color:      _textPrimary,
                      fontSize:   w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 4),
                Text('Today, 08:45 AM',
                    style: TextStyle(
                        color:    _textSecondary,
                        fontSize: w * 0.032)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.024, vertical: 5),
            decoration: BoxDecoration(
              color:        _successLight,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('Completed',
                style: TextStyle(
                  color:      _success,
                  fontSize:   w * 0.028,
                  fontWeight: FontWeight.w600,
                )),
          ),
        ],
      ),
    );
  }
}

// ── Route card ─────────────────────────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final double w, h;
  const _RouteCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        children: [
          _RouteRow(
            icon:    Icons.radio_button_checked_rounded,
            color:   _gold,
            label:   'Pickup',
            address: 'Airport Residential Area, Accra',
            time:    '08:45 AM',
            w:       w,
          ),
          Padding(
            padding: EdgeInsets.only(left: w * 0.045),
            child: Column(
              children: List.generate(
                  3,
                  (_) => Container(
                        height: 6,
                        width:  1.5,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color:  _divider,
                      )),
            ),
          ),
          _RouteRow(
            icon:    Icons.location_on_rounded,
            color:   _danger,
            label:   'Drop-off',
            address: 'Ridge, Accra',
            time:    '09:12 AM',
            w:       w,
          ),
        ],
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final IconData icon;
  final Color    color;
  final String   label, address, time;
  final double   w;

  const _RouteRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.address,
    required this.time,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: w * 0.030),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color:    _textSecondary,
                      fontSize: w * 0.028)),
              const SizedBox(height: 2),
              Text(address,
                  style: TextStyle(
                    color:      _textPrimary,
                    fontSize:   w * 0.036,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
        Text(time,
            style: TextStyle(
                color:    _textSecondary,
                fontSize: w * 0.030)),
      ],
    );
  }
}

// ── Driver card ────────────────────────────────────────────────────────────────

class _DriverCard extends StatelessWidget {
  final double w, h;
  const _DriverCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Row(
        children: [
          Container(
            width:  w * 0.13,
            height: w * 0.13,
            decoration: const BoxDecoration(
                color: Color(0xFF2C3E50), shape: BoxShape.circle),
            child: Icon(Icons.person_rounded,
                color: Colors.white, size: w * 0.065),
          ),
          SizedBox(width: w * 0.030),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Kwame Asante',
                    style: TextStyle(
                      color:      _textPrimary,
                      fontSize:   w * 0.040,
                      fontWeight: FontWeight.w700,
                    )),
                const SizedBox(height: 3),
                Text('Toyota Corolla  •  GT 1234-22',
                    style: TextStyle(
                        color:    _textSecondary,
                        fontSize: w * 0.032)),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.star_rounded, color: _gold, size: 14),
                  const SizedBox(width: 3),
                  Text('4.8',
                      style: TextStyle(
                        color:      _textPrimary,
                        fontSize:   w * 0.032,
                        fontWeight: FontWeight.w600,
                      )),
                ]),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('27 min',
                  style: TextStyle(
                    color:      _textPrimary,
                    fontSize:   w * 0.036,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 2),
              Text('Trip duration',
                  style: TextStyle(
                      color:    _textSecondary,
                      fontSize: w * 0.028)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Fare card ──────────────────────────────────────────────────────────────────

class _FareCard extends StatelessWidget {
  final double w, h;
  const _FareCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        _surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: _divider),
      ),
      child: Column(
        children: [
          _FareRow(label: 'Base fare',         value: 'GHS 12.00', w: w, h: h),
          _FareRow(label: 'Distance (14.2 km)', value: 'GHS 28.40', w: w, h: h),
          _FareRow(label: 'Booking fee',        value: 'GHS 2.50',  w: w, h: h),
          Padding(
            padding: EdgeInsets.symmetric(vertical: h * 0.010),
            child: const Divider(height: 1, color: _divider),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total',
                  style: TextStyle(
                    color:      _textPrimary,
                    fontSize:   w * 0.038,
                    fontWeight: FontWeight.w700,
                  )),
              Text('GHS 42.90',
                  style: TextStyle(
                    color:      _textPrimary,
                    fontSize:   w * 0.044,
                    fontWeight: FontWeight.w800,
                  )),
            ],
          ),
          SizedBox(height: h * 0.010),
          Row(
            children: [
              const Icon(Icons.phone_android_rounded,
                  color: _textSecondary, size: 14),
              SizedBox(width: w * 0.016),
              Text('Paid via MTN MoMo',
                  style: TextStyle(
                      color:    _textSecondary,
                      fontSize: w * 0.030)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  final String label, value;
  final double w, h;
  const _FareRow(
      {required this.label,
      required this.value,
      required this.w,
      required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: h * 0.008),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: _textSecondary, fontSize: w * 0.034)),
          Text(value,
              style: TextStyle(
                color:      _textPrimary,
                fontSize:   w * 0.034,
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

// ── Action row ─────────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final String rideId;
  final double w, h, bot;
  const _ActionRow(
      {required this.rideId,
      required this.w,
      required this.h,
      required this.bot});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () =>
                context.push(AppRoutes.rideDisputePath(rideId)),
            icon: const Icon(Icons.flag_outlined, size: 18),
            label: const Text('Dispute Fare'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _danger,
              side:  const BorderSide(color: _danger),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  EdgeInsets.symmetric(vertical: h * 0.018),
            ),
          ),
        ),
        SizedBox(width: w * 0.030),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () =>
                context.push(AppRoutes.rideReceiptPath(rideId)),
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text('View Receipt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
              padding:
                  EdgeInsets.symmetric(vertical: h * 0.018),
            ),
          ),
        ),
      ],
    );
  }
}
