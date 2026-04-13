import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/profile_provider.dart';
import '../../../app/router.dart' show AppRoutes;

// ── Design tokens ─────────────────────────────────────────────────────────────
const _surfaceWhite  = Color(0xFFFFFFFF);
const _surfaceGrey   = Color(0xFFF3F5F6);
const _offWhite      = Color(0xFFF6F7F8);
const _textPrimary   = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _textHint      = Color(0xFFBDBDBD);
const _gold          = Color(0xFFF5A623);
const _darkSlate     = Color(0xFF46535D);
const _error         = Color(0xFFEB5757);
const _errorLight    = Color(0xFFFDE8E8);
const _divider       = Color(0xFFE0E0E0);

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD 4.9 — Profile tab: masked identity, KYC badge, settings navigation.
// API: GET /v1/users/me  |  DELETE /v1/users/me (deactivate, 90-day retention)

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    final dataAsync = ref.watch(accountScreenProvider);

    return Scaffold(
      backgroundColor: _offWhite,
      body: dataAsync.when(
        loading: () => _LoadingSkeleton(w: w, h: h),
        error: (_, __) => _ErrorBody(
          w: w,
          h: h,
          onRetry: () => ref.invalidate(accountScreenProvider),
        ),
        data: (data) => _ProfileBody(data: data, w: w, h: h),
      ),
    );
  }
}

// ── Full body ─────────────────────────────────────────────────────────────────

class _ProfileBody extends StatelessWidget {
  final AccountScreenData data;
  final double w;
  final double h;
  const _ProfileBody(
      {required this.data, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final topPad    = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final notifCount = data.unreadNotificationCount;

    return Column(
      children: [
        _AppBar(
          w: w,
          h: h,
          topPad: topPad,
          hasUnread: notifCount > 0,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.only(bottom: bottomPad + h * 0.014),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Profile header ──
                _ProfileHeader(profile: data.profile, w: w, h: h),
                SizedBox(height: h * 0.022),

                // ── Personalisation & Safety ──
                _SectionLabel(label: 'PERSONALIZATION & SAFETY', w: w, h: h),
                _SectionCard(
                  w: w,
                  children: [
                    _MenuRow(
                      icon: Icons.location_on_outlined,
                      title: 'Saved Places',
                      subtitle: 'Home, office, and frequent sites',
                      onTap: () => context.push(AppRoutes.profileSavedPlaces),
                      w: w,
                      h: h,
                    ),
                    _RowDivider(w: w),
                    _MenuRow(
                      icon: Icons.notifications_outlined,
                      title: 'Notifications',
                      subtitle: 'Alerts, messages, and task updates',
                      badgeCount: notifCount > 0 ? notifCount : null,
                      onTap: () => context.push(AppRoutes.profileNotifications),
                      w: w,
                      h: h,
                    ),
                    _RowDivider(w: w),
                    _MenuRow(
                      icon: Icons.security_outlined,
                      title: 'Privacy & Security',
                      subtitle: '2FA, login history, and permissions',
                      onTap: () => context.push(AppRoutes.profilePrivacy),
                      w: w,
                      h: h,
                    ),
                    _RowDivider(w: w),
                    _MenuRow(
                      icon: Icons.contact_emergency_outlined,
                      title: 'Emergency Contacts',
                      subtitle: 'Trusted contacts for SOS alerts',
                      onTap: () => context.push(AppRoutes.profileEmergency),
                      w: w,
                      h: h,
                    ),
                  ],
                ),
                SizedBox(height: h * 0.022),

                // ── App Settings ──
                _SectionLabel(label: 'APP SETTINGS', w: w, h: h),
                _SectionCard(
                  w: w,
                  children: [
                    _MenuRow(
                      icon: Icons.tune_rounded,
                      title: 'App Preferences',
                      subtitle: 'Theme, data usage, and display',
                      onTap: () => context.push(AppRoutes.profilePreferences),
                      w: w,
                      h: h,
                    ),
                    _RowDivider(w: w),
                    _MenuRow(
                      icon: Icons.language_rounded,
                      title: 'Language',
                      subtitle: 'English, Twi, and more',
                      onTap: () => context.push(AppRoutes.profileLanguage),
                      w: w,
                      h: h,
                    ),
                    _RowDivider(w: w),
                    _MenuRow(
                      icon: Icons.history_rounded,
                      title: 'Activity & History',
                      subtitle: 'Past tasks, reviews, and logs',
                      onTap: () => context.go(AppRoutes.activity),
                      w: w,
                      h: h,
                    ),
                  ],
                ),
                SizedBox(height: h * 0.022),

                // ── Wallet ──
                _SectionLabel(label: 'WALLET', w: w, h: h),
                _SectionCard(
                  w: w,
                  children: [
                    _MenuRow(
                      icon: Icons.credit_card_rounded,
                      title: 'Payment Methods',
                      subtitle: 'MoMo, cards, and wallet balance',
                      onTap: () => context.push(AppRoutes.profilePayments),
                      w: w,
                      h: h,
                    ),
                  ],
                ),
                SizedBox(height: h * 0.022),

                // ── Rewards ──
                _SectionLabel(label: 'REWARDS', w: w, h: h),
                _SectionCard(
                  w: w,
                  children: [
                    _MenuRow(
                      icon: Icons.star_outline_rounded,
                      title: 'Loyalty Points',
                      subtitle: 'Earn points on every ride and job',
                      onTap: () => context.push(AppRoutes.profileLoyalty),
                      w: w,
                      h: h,
                    ),
                    _RowDivider(w: w),
                    _MenuRow(
                      icon: Icons.share_rounded,
                      title: 'Referral & Earn',
                      subtitle: 'Invite friends and earn GHS 10 each',
                      onTap: () => context.push(AppRoutes.profileReferral),
                      w: w,
                      h: h,
                    ),
                  ],
                ),
                SizedBox(height: h * 0.022),

                // ── Support ──
                _SectionLabel(label: 'SUPPORT', w: w, h: h),
                _SectionCard(
                  w: w,
                  children: [
                    _MenuRow(
                      icon: Icons.help_outline_rounded,
                      title: 'Support & Legal',
                      subtitle: 'FAQs, Contact, Terms of Service',
                      onTap: () => context.push(AppRoutes.profileSupport),
                      w: w,
                      h: h,
                    ),
                    _RowDivider(w: w),
                    _SignOutRow(w: w, h: h),
                  ],
                ),
                SizedBox(height: h * 0.022),

                // ── Deactivate ──
                _DeactivateLink(w: w, h: h),
                SizedBox(height: h * 0.022),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── App Bar ───────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final double w;
  final double h;
  final double topPad;
  final bool   hasUnread;
  const _AppBar({
    required this.w,
    required this.h,
    required this.topPad,
    required this.hasUnread,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _surfaceWhite,
      padding: EdgeInsets.only(
        top:    topPad + h * 0.012,
        bottom: h * 0.017,
        left:   w * 0.041,
        right:  w * 0.041,
      ),
      child: Row(
        children: [
          Text(
            'Account',
            style: TextStyle(
              fontSize:   w * 0.056,
              fontWeight: FontWeight.w700,
              color:      _textPrimary,
            ),
          ),
          const Spacer(),
          // Bell with optional unread dot
          GestureDetector(
            onTap: () => context.push(AppRoutes.notifications),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width:  w * 0.082,
              height: w * 0.082,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.notifications_outlined,
                    size:  w * 0.056,
                    color: _textPrimary,
                  ),
                  if (hasUnread)
                    Positioned(
                      top:   w * 0.010,
                      right: w * 0.010,
                      child: Container(
                        width:  w * 0.021,
                        height: w * 0.021,
                        decoration: const BoxDecoration(
                          color: _error,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile Header ────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  final AccountProfile profile;
  final double w;
  final double h;
  const _ProfileHeader(
      {required this.profile, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _surfaceWhite,
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: h * 0.028),
      child: Column(
        children: [
          // ── Avatar + camera badge ──
          GestureDetector(
            onTap: () => context.push(AppRoutes.profileEdit),
            child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              Container(
                width:  w * 0.231,
                height: w * 0.231,
                decoration: BoxDecoration(
                  color: const Color(0xFF78909C),
                  shape: BoxShape.circle,
                ),
                child: profile.avatarUrl != null
                    ? ClipOval(
                        child: Image.network(
                          profile.avatarUrl!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : Center(
                        child: Text(
                          profile.initials,
                          style: TextStyle(
                            fontSize:   w * 0.082,
                            fontWeight: FontWeight.w700,
                            color:      _surfaceWhite,
                          ),
                        ),
                      ),
              ),
              // Camera edit badge
              Container(
                width:  w * 0.077,
                height: w * 0.077,
                decoration: BoxDecoration(
                  color:  _gold,
                  shape:  BoxShape.circle,
                  border: Border.all(color: _surfaceWhite, width: 2.5),
                ),
                child: Icon(
                  Icons.photo_camera_rounded,
                  size:  w * 0.038,
                  color: _surfaceWhite,
                ),
              ),
            ],
          ),
          ),
          SizedBox(height: h * 0.017),

          // ── Display name ──
          Text(
            profile.displayName,
            style: TextStyle(
              fontSize:   w * 0.051,
              fontWeight: FontWeight.w700,
              color:      _textPrimary,
            ),
          ),
          SizedBox(height: h * 0.005),

          // ── Masked email ──
          Text(
            profile.maskedEmail,
            style: TextStyle(
              fontSize:   w * 0.033,
              fontWeight: FontWeight.w400,
              color:      _textSecondary,
            ),
          ),
          SizedBox(height: h * 0.003),

          // ── Masked phone ──
          Text(
            profile.maskedPhone,
            style: TextStyle(
              fontSize:   w * 0.033,
              fontWeight: FontWeight.w400,
              color:      _textSecondary,
            ),
          ),
          SizedBox(height: h * 0.017),

          // ── KYC badge ──
          if (profile.isKycVerified) _KycBadge(w: w, h: h),
        ],
      ),
    );
  }
}

class _KycBadge extends StatelessWidget {
  final double w;
  final double h;
  const _KycBadge({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.038,
        vertical:   h * 0.006,
      ),
      decoration: BoxDecoration(
        color:        Colors.transparent,
        borderRadius: BorderRadius.circular(w * 0.051),
        border:       Border.all(color: _gold, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded,
              size: w * 0.033, color: _gold),
          SizedBox(width: w * 0.010),
          Text(
            'KYC VERIFIED',
            style: TextStyle(
              fontSize:      w * 0.026,
              fontWeight:    FontWeight.w700,
              color:         _gold,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section Label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final double w;
  final double h;
  const _SectionLabel(
      {required this.label, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left:   w * 0.041,
        bottom: h * 0.008,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize:      w * 0.023,
          fontWeight:    FontWeight.w900,
          color:         _textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ── Section Card ──────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final List<Widget> children;
  final double w;
  const _SectionCard({required this.children, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _surfaceWhite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

// ── Row Divider (aligned to text start) ──────────────────────────────────────

class _RowDivider extends StatelessWidget {
  final double w;
  const _RowDivider({required this.w});

  @override
  Widget build(BuildContext context) {
    // Offset = horizontal padding + icon width + gap
    return Padding(
      padding: EdgeInsets.only(
        left: w * 0.041 + w * 0.115 + w * 0.031,
      ),
      child: const Divider(height: 1, color: _divider),
    );
  }
}

// ── Menu Row ──────────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final VoidCallback onTap;
  final int?         badgeCount;
  final double       w;
  final double       h;

  const _MenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.w,
    required this.h,
    this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical:   h * 0.017,
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width:  w * 0.115,
              height: w * 0.115,
              decoration: const BoxDecoration(
                color: _surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: w * 0.051, color: _textSecondary),
            ),
            SizedBox(width: w * 0.031),

            // Labels
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize:   w * 0.036,
                      fontWeight: FontWeight.w600,
                      color:      _textPrimary,
                    ),
                  ),
                  SizedBox(height: h * 0.003),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize:   w * 0.028,
                      fontWeight: FontWeight.w400,
                      color:      _textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Optional "N New" badge
            if (badgeCount != null) ...[
              _NewBadge(count: badgeCount!, w: w),
              SizedBox(width: w * 0.015),
            ],

            // Chevron
            Icon(
              Icons.chevron_right_rounded,
              size:  w * 0.051,
              color: _textHint,
            ),
          ],
        ),
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  final int    count;
  final double w;
  const _NewBadge({required this.count, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.021,
        vertical:   w * 0.008,
      ),
      decoration: BoxDecoration(
        color:        _gold,
        borderRadius: BorderRadius.circular(w * 0.041),
      ),
      child: Text(
        '$count New',
        style: TextStyle(
          fontSize:   w * 0.026,
          fontWeight: FontWeight.w700,
          color:      _surfaceWhite,
        ),
      ),
    );
  }
}

// ── Sign Out Row ──────────────────────────────────────────────────────────────

class _SignOutRow extends StatelessWidget {
  final double w;
  final double h;
  const _SignOutRow({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _confirmSignOut(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical:   h * 0.017,
        ),
        child: Row(
          children: [
            // Red icon circle
            Container(
              width:  w * 0.115,
              height: w * 0.115,
              decoration: const BoxDecoration(
                color: _errorLight,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.logout_rounded,
                size:  w * 0.051,
                color: _error,
              ),
            ),
            SizedBox(width: w * 0.031),

            // Title only (no subtitle for sign out)
            Expanded(
              child: Text(
                'Sign Out',
                style: TextStyle(
                  fontSize:   w * 0.036,
                  fontWeight: FontWeight.w600,
                  color:      _error,
                ),
              ),
            ),

            Icon(
              Icons.chevron_right_rounded,
              size:  w * 0.051,
              color: _error.withValues(alpha: 0.50),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Sign Out',
          style: TextStyle(
            fontSize:   MediaQuery.sizeOf(context).width * 0.046,
            fontWeight: FontWeight.w700,
            color:      _textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out?',
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width * 0.033,
            color:    _textSecondary,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            MediaQuery.sizeOf(context).width * 0.031,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: _darkSlate),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: clear JWT tokens + navigate to login
            },
            child: Text(
              'Sign Out',
              style: TextStyle(
                color:      _error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Deactivate Link ───────────────────────────────────────────────────────────
// EDD § User Module: soft-delete — data retained 90 days, 24-hour recovery.
// DELETE /v1/users/me

class _DeactivateLink extends StatelessWidget {
  final double w;
  final double h;
  const _DeactivateLink({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _confirmDeactivate(context),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: h * 0.005),
        child: Center(
          child: Text(
            'Deactivate My Account',
            style: TextStyle(
              fontSize:   w * 0.033,
              fontWeight: FontWeight.w500,
              color:      _error,
              decoration: TextDecoration.underline,
              decorationColor: _error,
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeactivate(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Deactivate Account?',
          style: TextStyle(
            fontSize:   w * 0.046,
            fontWeight: FontWeight.w700,
            color:      _textPrimary,
          ),
        ),
        content: Text(
          'Your account will be deactivated. Data is retained for 90 days '
          'and you can recover within 24 hours.',
          style: TextStyle(
            fontSize: w * 0.033,
            color:    _textSecondary,
            height:   1.4,
          ),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(w * 0.031),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: _darkSlate)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              // TODO: DELETE /v1/users/me — then navigate to auth screen
            },
            child: Text(
              'Deactivate',
              style: TextStyle(
                color:      _error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
    final topPad = MediaQuery.paddingOf(context).top;
    return Column(
      children: [
        // App bar shimmer
        Container(
          color:   _surfaceWhite,
          padding: EdgeInsets.only(
              top:    topPad + h * 0.012,
              bottom: h * 0.017,
              left:   w * 0.041,
              right:  w * 0.041),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Shimmer(w: w * 0.26, h: h * 0.028),
              _Shimmer(w: w * 0.056, h: w * 0.056, r: w * 0.056),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Profile header skeleton
                Container(
                  color:   _surfaceWhite,
                  padding: EdgeInsets.symmetric(vertical: h * 0.028),
                  child: Column(
                    children: [
                      _Shimmer(w: w * 0.231, h: w * 0.231, r: w * 0.231),
                      SizedBox(height: h * 0.017),
                      _Shimmer(w: w * 0.51, h: h * 0.026),
                      SizedBox(height: h * 0.008),
                      _Shimmer(w: w * 0.41, h: h * 0.019),
                      SizedBox(height: h * 0.006),
                      _Shimmer(w: w * 0.36, h: h * 0.019),
                      SizedBox(height: h * 0.017),
                      _Shimmer(w: w * 0.31, h: h * 0.031, r: w * 0.051),
                    ],
                  ),
                ),
                SizedBox(height: h * 0.022),
                // Section skeletons
                _Shimmer(w: w * 0.51,     h: h * 0.014, r: 4),
                SizedBox(height: h * 0.008),
                _Shimmer(w: double.infinity, h: h * 0.17, r: 0),
                SizedBox(height: h * 0.022),
                _Shimmer(w: w * 0.36,     h: h * 0.014, r: 4),
                SizedBox(height: h * 0.008),
                _Shimmer(w: double.infinity, h: h * 0.17, r: 0),
                SizedBox(height: h * 0.022),
                _Shimmer(w: w * 0.23,     h: h * 0.014, r: 4),
                SizedBox(height: h * 0.008),
                _Shimmer(w: double.infinity, h: h * 0.12, r: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double w;
  final double h;
  final double r;
  const _Shimmer({required this.w, required this.h, this.r = 4});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:  w,
      height: h,
      decoration: BoxDecoration(
        color:        const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(r),
      ),
    );
  }
}

// ── Error Body ────────────────────────────────────────────────────────────────

class _ErrorBody extends StatelessWidget {
  final double       w;
  final double       h;
  final VoidCallback onRetry;
  const _ErrorBody(
      {required this.w, required this.h, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.082),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_off_outlined,
                size: w * 0.154, color: _textHint),
            SizedBox(height: h * 0.019),
            Text(
              'Could not load account',
              style: TextStyle(
                fontSize:   w * 0.041,
                fontWeight: FontWeight.w700,
                color:      _textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.009),
            Text(
              'Check your connection and try again.',
              style: TextStyle(
                  fontSize: w * 0.033, color: _textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: h * 0.028),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.077, vertical: h * 0.017),
                decoration: BoxDecoration(
                  color:        _darkSlate,
                  borderRadius: BorderRadius.circular(w * 0.021),
                ),
                child: Text(
                  'Try Again',
                  style: TextStyle(
                    fontSize:   w * 0.038,
                    fontWeight: FontWeight.w600,
                    color:      _surfaceWhite,
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
