import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/privacy_security_provider.dart';

// ── Screen ────────────────────────────────────────────────────────────────────
// PRD § 9 Safety & Security, § 9.5 Ghana DPA Compliance, § 9.6 Client KYC.
// EDD § User Module, § Verification Module, § 10.2 Data Encryption.
// API: GET /v1/users/me, GET /v1/verification/status, DELETE /v1/users/me

class PrivacySecurityScreen extends ConsumerWidget {
  const PrivacySecurityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size   = MediaQuery.sizeOf(context);
    final w      = size.width;
    final h      = size.height;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final state = ref.watch(privacySecurityProvider);

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: _buildAppBar(context, w),
      body: state.isLoading
          ? _LoadingSkeleton(w: w, h: h)
          : state.data == null
              ? MyShopErrorBody(
                  message: 'Could not load settings',
                  onRetry: () =>
                      ref.read(privacySecurityProvider.notifier).reload(),
                )
              : SingleChildScrollView(
                  padding: EdgeInsets.only(
                    bottom: bottom + h * 0.032,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: h * 0.022),

                      // ── Identity Verification ────────────────────────────
                      _SectionTitle(title: 'Identity Verification', w: w, h: h),
                      SizedBox(height: h * 0.014),
                      _KycStatusCard(
                          status: state.data!.kycStatus, w: w, h: h),
                      SizedBox(height: h * 0.012),
                      _KycDescription(
                          status: state.data!.kycStatus, w: w, h: h),

                      SizedBox(height: h * 0.028),

                      // ── Account Security ─────────────────────────────────
                      _SectionTitle(title: 'Account Security', w: w, h: h),
                      SizedBox(height: h * 0.014),
                      _AccountSecurityCard(
                        data: state.data!,
                        w: w,
                        h: h,
                      ),

                      SizedBox(height: h * 0.028),

                      // ── Data & Privacy ───────────────────────────────────
                      _SectionTitle(title: 'Data & Privacy', w: w, h: h),
                      SizedBox(height: h * 0.014),
                      _DataPrivacyInfoBox(w: w, h: h),

                      SizedBox(height: h * 0.034),

                      // ── Danger Zone ──────────────────────────────────────
                      _DangerZoneSection(w: w, h: h),

                      SizedBox(height: h * 0.034),

                      // ── Footer ───────────────────────────────────────────
                      _Footer(w: w, h: h),
                      SizedBox(height: h * 0.016),
                    ],
                  ),
                ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, double w) {
    return AppBar(
      backgroundColor: MyShopColors.surfaceWhite,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.arrow_back,
          color: MyShopColors.textPrimary,
          size: w * 0.052,
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        'Privacy & Security',
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.050,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
          height: 1.3,
        ),
      ),
      centerTitle: false,
    );
  }
}

// ── Section title ─────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final double w;
  final double h;
  const _SectionTitle(
      {required this.title, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Text(
        title,
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.044,
          fontWeight: FontWeight.w700,
          color: MyShopColors.textPrimary,
          height: 1.3,
        ),
      ),
    );
  }
}

// ── KYC Status card ───────────────────────────────────────────────────────────

class _KycStatusCard extends StatelessWidget {
  final KycStatus status;
  final double w;
  final double h;
  const _KycStatusCard(
      {required this.status, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final (bg, border, iconBg, iconColor, labelColor, label) =
        _resolveStyle(status);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.044,
          vertical: h * 0.018,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border, width: 1.5),
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: w * 0.100,
              height: w * 0.100,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _resolveIcon(status),
                color: iconColor,
                size: w * 0.050,
              ),
            ),
            SizedBox(width: w * 0.034),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'KYC STATUS',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.026,
                    fontWeight: FontWeight.w900,
                    color: labelColor.withValues(alpha: 0.7),
                    letterSpacing: 1.2,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: h * 0.003),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: w * 0.044,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static (Color, Color, Color, Color, Color, String) _resolveStyle(
      KycStatus s) {
    return switch (s) {
      KycStatus.verified => (
          MyShopColors.successLight,
          MyShopColors.success,
          MyShopColors.success.withValues(alpha: 0.18),
          MyShopColors.success,
          MyShopColors.success,
          'Verified',
        ),
      KycStatus.pending => (
          MyShopColors.warningLight,
          MyShopColors.warning,
          MyShopColors.warning.withValues(alpha: 0.18),
          MyShopColors.warning,
          MyShopColors.warning,
          'Pending',
        ),
      KycStatus.rejected => (
          MyShopColors.errorLight,
          MyShopColors.error,
          MyShopColors.error.withValues(alpha: 0.18),
          MyShopColors.error,
          MyShopColors.error,
          'Rejected',
        ),
      KycStatus.unverified => (
          MyShopColors.surfaceGrey,
          MyShopColors.divider,
          MyShopColors.divider.withValues(alpha: 0.5),
          MyShopColors.textHint,
          MyShopColors.textSecondary,
          'Not Verified',
        ),
    };
  }

  static IconData _resolveIcon(KycStatus s) => switch (s) {
        KycStatus.verified   => Icons.verified_user_rounded,
        KycStatus.pending    => Icons.hourglass_top_rounded,
        KycStatus.rejected   => Icons.gpp_bad_rounded,
        KycStatus.unverified => Icons.shield_outlined,
      };
}

// ── KYC Description ───────────────────────────────────────────────────────────

class _KycDescription extends StatelessWidget {
  final KycStatus status;
  final double w;
  final double h;
  const _KycDescription(
      {required this.status, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    final text = switch (status) {
      KycStatus.verified =>
        'Your identity documents have been verified against national '
            'databases. Verified users enjoy higher transaction limits.',
      KycStatus.pending =>
        'Your documents are under review. Verification typically '
            'completes within a few minutes.',
      KycStatus.rejected =>
        'Verification was unsuccessful. Please resubmit your documents '
            'to continue using all platform features.',
      KycStatus.unverified =>
        'Verify your identity to unlock higher transaction limits and '
            'the ID Verified badge visible to artisans.',
    };

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Raleway',
          fontSize: w * 0.033,
          fontWeight: FontWeight.w400,
          color: MyShopColors.textSecondary,
          height: 1.55,
        ),
      ),
    );
  }
}

// ── Account Security card ─────────────────────────────────────────────────────

class _AccountSecurityCard extends StatelessWidget {
  final PrivacySecurityData data;
  final double w;
  final double h;
  const _AccountSecurityCard(
      {required this.data, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.044),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _SecurityRow(
            icon: Icons.smartphone_outlined,
            title: 'Primary Phone',
            subtitle: data.maskedPhone,
            onTap: () {/* TODO: navigate to change-phone OTP flow */},
            w: w,
            h: h,
          ),
          _RowDivider(w: w),
          _SecurityRow(
            icon: Icons.badge_outlined,
            title: 'National ID',
            subtitle: data.maskedNationalId,
            onTap: () {/* TODO: navigate to KYC submission */},
            w: w,
            h: h,
          ),
          _RowDivider(w: w),
          _SecurityRow(
            icon: Icons.fingerprint_rounded,
            title: 'Biometric Login',
            subtitle: data.biometricLabel,
            onTap: () {/* TODO: navigate to biometric settings */},
            w: w,
            h: h,
          ),
        ],
      ),
    );
  }
}

class _SecurityRow extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final VoidCallback onTap;
  final double w;
  final double h;

  const _SecurityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.041,
          vertical: h * 0.016,
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.092,
              height: w * 0.092,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: MyShopColors.textSecondary, size: w * 0.046),
            ),
            SizedBox(width: w * 0.031),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: w * 0.038,
                      fontWeight: FontWeight.w600,
                      color: MyShopColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: h * 0.003),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: w * 0.031,
                      fontWeight: FontWeight.w400,
                      color: MyShopColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: MyShopColors.textHint,
              size: w * 0.052,
            ),
          ],
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  final double w;
  const _RowDivider({required this.w});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: w * 0.041 + w * 0.092 + w * 0.031),
      child: const Divider(color: MyShopColors.divider, height: 1, thickness: 1),
    );
  }
}

// ── Data & Privacy info box ───────────────────────────────────────────────────
// PRD § 9.5: Ghana Data Protection Act, 2012 (Act 843) compliance notice.

class _DataPrivacyInfoBox extends StatelessWidget {
  final double w;
  final double h;
  const _DataPrivacyInfoBox({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: w * 0.038,
          vertical: h * 0.016,
        ),
        decoration: BoxDecoration(
          color: MyShopColors.infoLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MyShopColors.info.withValues(alpha: 0.35), width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: MyShopColors.info,
              size: w * 0.046,
            ),
            SizedBox(width: w * 0.028),
            Expanded(
              child: Text(
                'Your data is processed in accordance with the Data '
                'Protection Act, 2012 (Act 843). We use industry-standard '
                'encryption for all sensitive information.',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.033,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.info,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Danger Zone section ───────────────────────────────────────────────────────
// EDD § User Module: DELETE /v1/users/me → soft delete, 90-day retention,
// 24h recovery window. Blocked if outstanding clawback balance (edge case #51).

class _DangerZoneSection extends ConsumerWidget {
  final double w;
  final double h;
  const _DangerZoneSection({required this.w, required this.h});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDeleting =
        ref.watch(privacySecurityProvider).isDeletingAccount;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Danger Zone" label
          Row(
            children: [
              Icon(
                Icons.report_problem_outlined,
                color: MyShopColors.error,
                size: w * 0.044,
              ),
              SizedBox(width: w * 0.018),
              Text(
                'Danger Zone',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.040,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.error,
                  height: 1.3,
                ),
              ),
            ],
          ),
          SizedBox(height: h * 0.016),

          // Delete Account heading
          Text(
            'Delete Account',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.042,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
              height: 1.3,
            ),
          ),
          SizedBox(height: h * 0.008),

          // Description
          Text(
            'Permanently remove your account and all associated data. '
            'This action is irreversible and will close all active services.',
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize: w * 0.033,
              fontWeight: FontWeight.w400,
              color: MyShopColors.textSecondary,
              height: 1.55,
            ),
          ),
          SizedBox(height: h * 0.022),

          // Proceed with Deletion button
          SizedBox(
            width: double.infinity,
            height: h * 0.064,
            child: Material(
              color: MyShopColors.error,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: isDeleting
                    ? null
                    : () => _confirmDelete(context, ref),
                borderRadius: BorderRadius.circular(8),
                splashColor: Colors.white.withValues(alpha: 0.15),
                child: Center(
                  child: isDeleting
                      ? SizedBox(
                          width: w * 0.052,
                          height: w * 0.052,
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline_rounded,
                              color: Colors.white,
                              size: w * 0.046,
                            ),
                            SizedBox(width: w * 0.025),
                            Text(
                              'Proceed with Deletion',
                              style: TextStyle(
                                fontFamily: 'Raleway',
                                fontSize: w * 0.040,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final w = MediaQuery.sizeOf(ctx).width;
        final h = MediaQuery.sizeOf(ctx).height;
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          contentPadding: EdgeInsets.fromLTRB(
              w * 0.055, h * 0.030, w * 0.055, h * 0.022),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Error icon
              Container(
                width: w * 0.114,
                height: w * 0.114,
                decoration: const BoxDecoration(
                  color: MyShopColors.errorLight,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.delete_forever_rounded,
                    color: MyShopColors.error, size: w * 0.058),
              ),
              SizedBox(height: h * 0.016),
              Text(
                'Delete your account?',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.044,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                  height: 1.3,
                ),
              ),
              SizedBox(height: h * 0.010),
              Text(
                'Your account and all data will be queued for permanent '
                'deletion. You have 24 hours to cancel this action by '
                'logging back in. After 90 days, all data is purged.',
                style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: w * 0.033,
                  fontWeight: FontWeight.w400,
                  color: MyShopColors.textSecondary,
                  height: 1.55,
                ),
              ),
              SizedBox(height: h * 0.026),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: MyShopColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding:
                            EdgeInsets.symmetric(vertical: h * 0.015),
                      ),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: w * 0.036,
                          fontWeight: FontWeight.w600,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: w * 0.030),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: MyShopColors.error,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding:
                            EdgeInsets.symmetric(vertical: h * 0.015),
                      ),
                      child: Text(
                        'Delete',
                        style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: w * 0.036,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      await ref
          .read(privacySecurityProvider.notifier)
          .deleteAccount();
      // TODO: on success, clear tokens and navigate to login
    }
  }
}

// ── Footer ────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final double w;
  final double h;
  const _Footer({required this.w, required this.h});

  // A short session ID derived from the current session — for display only.
  static String get _sessionId {
    final now = DateTime.now();
    final code = (now.millisecondsSinceEpoch % 999999).toRadixString(36)
        .toUpperCase()
        .padLeft(6, '0');
    return '${code.substring(0, 3)}-${code.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.044),
      child: Column(
        children: [
          Center(
            child: Text(
              'SECURE SESSION ID: $_sessionId',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.026,
                fontWeight: FontWeight.w600,
                color: MyShopColors.textHint,
                letterSpacing: 1.0,
                height: 1.5,
              ),
            ),
          ),
          SizedBox(height: h * 0.004),
          Center(
            child: Text(
              'MyShop App v1.2.0  •  Security Patch: May 2026',
              style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: w * 0.026,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textHint,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  final double w;
  final double h;
  const _LoadingSkeleton({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.044, vertical: h * 0.022),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Shimmer(w: w * 0.40, h: h * 0.022),
          SizedBox(height: h * 0.014),
          _Shimmer(w: double.infinity, h: h * 0.080),
          SizedBox(height: h * 0.012),
          _Shimmer(w: double.infinity, h: h * 0.040),
          SizedBox(height: h * 0.028),
          _Shimmer(w: w * 0.35, h: h * 0.022),
          SizedBox(height: h * 0.014),
          _Shimmer(w: double.infinity, h: h * 0.160),
          SizedBox(height: h * 0.028),
          _Shimmer(w: w * 0.30, h: h * 0.022),
          SizedBox(height: h * 0.014),
          _Shimmer(w: double.infinity, h: h * 0.070),
        ],
      ),
    );
  }
}

class _Shimmer extends StatelessWidget {
  final double w;
  final double h;
  const _Shimmer({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: MyShopColors.divider,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

