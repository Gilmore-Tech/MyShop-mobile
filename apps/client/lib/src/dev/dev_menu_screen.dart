import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app/router.dart';
import '../features/ride/providers/ride_provider.dart' show MatchedDriver;

// Design tokens
const _bg          = Color(0xFFF6F7F8);
const _gold        = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _surfaceWhite = Color(0xFFFFFFFF);

// ── Mock objects needed by screens that require route extras ───────────────────

const _mockDriver = MatchedDriver(
  name:               'Kofi Mensah',
  vehicle:            'Midnight Black Toyota Camry Hybrid',
  plateNumber:        'GR-4557-23',
  rating:             4.92,
  minutesAway:        3,
  driversAvailable:   3,
  tripCount:          1450,
  isVerified:         true,
  isPoliceChecked:    true,
  maskedPhone:        '+233 ••• ••• 42',
  vehicleTier:        'Premier Comfort',
  baseFarePesewas:    1200,
  distanceFarePesewas: 1550,
  distanceKm:         5.2,
  bookingFeePesewas:  250,
);

const _mockRideId = 'RIDE-2041';
const _mockJobId  = 'JOB-001';
const _mockBidId  = 'BID-001';

// ── Dev Menu ──────────────────────────────────────────────────────────────────

class DevMenuScreen extends StatelessWidget {
  const DevMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _textPrimary,
        foregroundColor: Colors.white,
        title: Text(
          'Dev Screen Navigator',
          style: TextStyle(
            fontSize:   w * 0.046,
            fontWeight: FontWeight.w700,
            color:      Colors.white,
          ),
        ),
        actions: [
          Container(
            margin: EdgeInsets.only(right: w * 0.041, top: 8, bottom: 8),
            padding: EdgeInsets.symmetric(horizontal: w * 0.026, vertical: 4),
            decoration: BoxDecoration(
              color:        _gold,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'DEV',
              style: TextStyle(
                fontSize:   w * 0.026,
                fontWeight: FontWeight.w900,
                color:      Colors.white,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [

          // ── Auth Flow ────────────────────────────────────────────────────────
          _Section(label: 'AUTH FLOW', children: [
            _Tile('Phone Input',      () => context.push(AppRoutes.authPhone)),
            _Tile('OTP Verification', () => context.push(AppRoutes.authOtp)),
          ]),

          // ── Main Tabs ────────────────────────────────────────────────────────
          _Section(label: 'MAIN TABS', children: [
            _Tile('Home',      () => context.go(AppRoutes.home)),
            _Tile('Services',  () => context.go(AppRoutes.services)),
            _Tile('Activity',  () => context.go(AppRoutes.activity)),
            _Tile('Profile',   () => context.go(AppRoutes.profile)),
          ]),

          // ── Ride Flow ────────────────────────────────────────────────────────
          _Section(label: 'RIDE FLOW', color: const Color(0xFF2F80ED), children: [
            _Tile('Destination Search',  () => context.push(AppRoutes.rideSearch)),
            _Tile('Fare Estimate / Plan Trip', () => context.push(AppRoutes.rideEstimate)),
            _Tile('Add Stop',            () => context.push(AppRoutes.rideStops)),
            _Tile('Driver Matching',     () => context.push(AppRoutes.rideMatching)),
            _Tile('Driver Found',        () => context.push(AppRoutes.rideDriverFound, extra: _mockDriver)),
            _Tile('Ride Tracking',       () => context.push(AppRoutes.rideTracking, extra: _mockDriver)),
            _Tile('Ride Complete',       () => context.push(AppRoutes.rideComplete)),
            _Tile('Ride Receipt',        () => context.push(AppRoutes.rideReceiptPath(_mockRideId))),
            _Tile('Ride Dispute',        () => context.push(AppRoutes.rideDisputePath(_mockRideId))),
          ]),

          // ── Services Flow ────────────────────────────────────────────────────
          _Section(label: 'SERVICES FLOW', color: _gold, children: [
            _Tile('Job Form (New Job)',   () => context.push(AppRoutes.jobNew)),
            _Tile('Job Detail',          () => context.push(AppRoutes.jobDetailPath(_mockJobId))),
            _Tile('Bid Detail',          () => context.push(AppRoutes.jobBidsPath(_mockJobId, _mockBidId))),
            _Tile('Bid Review',          () => context.push(
                                                AppRoutes.jobBidReviewPath(_mockJobId),
                                                extra: _mockBidId)),
            _Tile('Supplement Review',   () => context.push(AppRoutes.jobSupplementPath(_mockJobId))),
            _Tile('Active Job',          () => context.push(AppRoutes.jobActivePath(_mockJobId))),
            _Tile('Job Tracking',        () => context.push(AppRoutes.jobTrackingPath(_mockJobId))),
            _Tile('Job Summary',         () => context.push(AppRoutes.jobSummaryPath(_mockJobId))),
            _Tile('Job Complete / Rate', () => context.push(AppRoutes.jobCompletePath(_mockJobId))),
            _Tile('Job Receipt',         () => context.push(AppRoutes.jobReceiptPath(_mockJobId))),
            _Tile('Job Dispute',         () => context.push(AppRoutes.jobDisputePath(_mockJobId))),
            _Tile('Payment',             () => context.push(AppRoutes.jobPaymentPath(_mockJobId))),
          ]),

          // ── Activity & History ───────────────────────────────────────────────
          _Section(label: 'ACTIVITY & HISTORY', color: const Color(0xFF27AE60), children: [
            _Tile('Activity List',        () => context.push(AppRoutes.activity)),
            _Tile('Ride History Detail',  () => context.push(AppRoutes.activityRidePath(_mockRideId))),
            _Tile('Job History Detail',   () => context.push(AppRoutes.activityJobPath(_mockJobId))),
          ]),

          // ── Profile & Settings ───────────────────────────────────────────────
          _Section(label: 'PROFILE & SETTINGS', color: const Color(0xFF46535D), children: [
            _Tile('Profile',              () => context.push(AppRoutes.profile)),
            _Tile('Edit Profile',         () => context.push(AppRoutes.profileEdit)),
            _Tile('Saved Locations',      () => context.push(AppRoutes.profileSavedPlaces)),
            _Tile('Notification Settings',() => context.push(AppRoutes.profileNotifications)),
            _Tile('Privacy & Security',   () => context.push(AppRoutes.profilePrivacy)),
            _Tile('App Preferences',      () => context.push(AppRoutes.profilePreferences)),
            _Tile('Language Settings',    () => context.push(AppRoutes.profileLanguage)),
            _Tile('Support & Legal',      () => context.push(AppRoutes.profileSupport)),
            _Tile('Referral',             () => context.push(AppRoutes.profileReferral)),
            _Tile('Payment Methods',      () => context.push(AppRoutes.profilePayments)),
            _Tile('Emergency Contacts',   () => context.push(AppRoutes.profileEmergency)),
            _Tile('Loyalty Points',       () => context.push(AppRoutes.profileLoyalty)),
          ]),

          // ── Overlays & Utilities ─────────────────────────────────────────────
          _Section(label: 'OVERLAYS & UTILITIES', color: const Color(0xFFEB5757), children: [
            _Tile('In-App Chat',          () => context.push(AppRoutes.chat)),
            _Tile('Emergency / SOS',      () => context.push(AppRoutes.safetyEmergency)),
            _Tile('Share Tracking',       () => context.push(AppRoutes.safetyShare)),
            _Tile('Notifications List',   () => context.push(AppRoutes.notifications)),
          ]),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Section ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String           label;
  final List<Widget>     children;
  final Color            color;

  const _Section({
    required this.label,
    required this.children,
    this.color = _textPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(w * 0.041, w * 0.051, w * 0.041, w * 0.021),
          child: Row(
            children: [
              Container(
                width:  w * 0.010,
                height: w * 0.036,
                decoration: BoxDecoration(
                  color:        color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: w * 0.026),
              Text(
                label,
                style: TextStyle(
                  fontSize:      w * 0.028,
                  fontWeight:    FontWeight.w900,
                  color:         _textSecondary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: w * 0.041),
          decoration: BoxDecoration(
            color:        _surfaceWhite,
            borderRadius: BorderRadius.circular(w * 0.031),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset:     const Offset(0, 2),
              ),
            ],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _Tile extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;

  const _Tile(this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    return Column(
      children: [
        InkWell(
          onTap:         onTap,
          borderRadius:  BorderRadius.circular(w * 0.031),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: w * 0.041,
              vertical:   w * 0.036,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize:   w * 0.038,
                      fontWeight: FontWeight.w500,
                      color:      _textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size:  w * 0.051,
                  color: _textSecondary,
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: w * 0.041),
          child: const Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
        ),
      ],
    );
  }
}
