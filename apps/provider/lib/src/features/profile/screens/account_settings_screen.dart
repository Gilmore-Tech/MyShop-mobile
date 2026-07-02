import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';
import '../../auth/providers/current_user_provider.dart';
import '../../earnings/providers/earnings_providers.dart';
import '../../earnings/providers/ratings_provider.dart';
import '../providers/provider_type_provider.dart';
import '../providers/verification_provider.dart';
import '../widgets/profile_read_only_note.dart';
import '../widgets/settings_list_tile.dart';
import '../widgets/settings_section.dart';

/// Account Settings hub — root screen for the bottom-nav "Account" tab.
///
/// Figma: nodes 298:21316 (driver pending), 304:22986 (driver verified),
///        311:24320 (artisan)
/// PRD Reference: PRD 5.4
///
/// Layout (top to bottom):
///   1. Header: avatar, name, role badge, verification chip, contact info
///   2. Edit Profile + KYC status buttons row
///   3. Verification banner (in-progress / verified state)
///   4. Performance card (Trips/Jobs Today, Earnings, Rating)
///   5. General Settings section
///   6. App & Security section
///   7. Support section
///   8. Deactivate Account
///   9. Compliance Summary card
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  Future<void> _showLogoutDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MyShopColors.surfaceWhite,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Log out?',
          style: TextStyle(
            fontFamily: 'Raleway',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: MyShopColors.textPrimary,
          ),
        ),
        content: Text(
          'You\'ll need to sign in again to access your account.',
          style: MyShopTypography.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: MyShopTypography.button.copyWith(
                color: MyShopColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Log Out',
              style: MyShopTypography.button.copyWith(
                color: MyShopColors.error,
              ),
            ),
          ),
        ],
      ),
    );
    debugPrint('[AccountSettings] logout dialog confirmed=$confirmed '
        'context.mounted=${context.mounted}');
    if (confirmed == true && context.mounted) {
      debugPrint('[AccountSettings] invoking controller.logout()');
      await ref.read(authControllerProvider.notifier).logout();
      debugPrint('[AccountSettings] controller.logout() returned');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerType = ref.watch(providerTypeProvider);
    final isDriver = providerType.isDriver;
    final user = ref.watch(currentUserProvider);
    final cardAsync = ref.watch(activeTodayCardProvider);
    // Real rating summary so the Performance card shows the actual
    // average / count instead of the hardcoded "--" placeholder. The
    // backend's GET /providers/me/ratings returns 0/empty for fresh
    // accounts; we render that as "New" rather than a fake number.
    final ratingsAsync = ref.watch(providerRatingsProvider);
    final ratingDisplay = ratingsAsync.when(
      loading: () => '—',
      error: (_, __) => '!',
      data: (r) => r.hasRatings ? r.averageDisplay : 'New',
    );
    final profilePhoto = ref.watch(providerProfilePhotoDisplayProvider);

    // Derive verification status from the user's profile
    final driverProfile = user?.driverProfile;
    final artisanProfile = user?.artisanProfile;
    final verificationStatus = isDriver
        ? (driverProfile?.verificationStatus ?? 'pending')
        : (artisanProfile?.verificationStatus ?? 'pending');
    final kycStatus = isDriver
        ? (driverProfile?.kycStatus ?? 'pending')
        : (artisanProfile?.kycStatus ?? 'pending');
    final policeCheckStatus = isDriver
        ? (driverProfile?.policeCheckStatus ?? 'pending')
        : (artisanProfile?.policeCheckStatus ?? 'pending');
    final isVerified = verificationStatus == 'approved';

    // Vehicle info subtitle
    final vehicleSubtitle = driverProfile != null &&
            driverProfile.vehicleMake != null &&
            driverProfile.vehiclePlate != null
        ? '${driverProfile.vehicleMake} ${driverProfile.vehicleModel ?? ''} (${driverProfile.vehiclePlate})'
        : 'Not set up yet';

    // Payout subtitle
    final payoutSubtitle = (isDriver
                ? driverProfile?.payoutAccountNumber
                : artisanProfile?.payoutAccountNumber) !=
            null
        ? '${isDriver ? driverProfile?.payoutMethod ?? 'MoMo' : artisanProfile?.payoutMethod ?? 'MoMo'}: ••• ${(isDriver ? driverProfile!.payoutAccountNumber! : artisanProfile!.payoutAccountNumber!).substring((isDriver ? driverProfile!.payoutAccountNumber! : artisanProfile!.payoutAccountNumber!).length > 4 ? (isDriver ? driverProfile!.payoutAccountNumber! : artisanProfile!.payoutAccountNumber!).length - 4 : 0)}'
        : 'Not set up yet';

    // KYC button label and style
    final kycLabel = kycStatus == 'approved'
        ? 'KYC: Verified'
        : 'KYC: ${_capitalize(kycStatus)}';
    final kycColor =
        kycStatus == 'approved' ? MyShopColors.success : MyShopColors.warning;
    final kycBg = kycStatus == 'approved'
        ? MyShopColors.successLight
        : MyShopColors.warningLight;

    // Today's earnings for performance card — sourced from the homepage
    // today-card endpoint, scoped to the active role. Uses the
    // gross-minus-commission helper rather than `netEarningsPesewas`
    // because the latter is 0 for cash bookings (artisan keeps the cash;
    // commission becomes a Clawback row).
    final todayEarnings = cardAsync.when(
      data: (c) => _formatGhs(c.effectiveEarningsPesewas),
      loading: () => '...',
      error: (_, __) => '0',
    );
    final todayTrips = cardAsync.when(
      data: (c) => '${c.bookingsCount}',
      loading: () => '...',
      error: (_, __) => '0',
    );

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // ── 1. Top header bar ──
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md, MyShopSpacing.md, MyShopSpacing.md, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Account Settings',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            const Divider(
                height: 1, thickness: 0.5, color: MyShopColors.divider),
            const SizedBox(height: MyShopSpacing.md),

            // ── 2. Identity card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _IdentityCard(
                isDriver: isDriver,
                fullName: user?.displayName ?? 'Provider',
                phone: user?.phone ?? '',
                email: user?.email ?? '',
                photoUrl: profilePhoto.url,
                localPhoto: profilePhoto.localFile,
                verificationStatus: verificationStatus,
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── 3. Action buttons row ──
            // Profile details are read-only for providers — they can view
            // their information but changes must be made by an admin. Only
            // the KYC / documents status entry point remains here.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: OutlinedButton.icon(
                onPressed: () => context.push('/account/documents'),
                icon: const Icon(Icons.shield_outlined, size: 14),
                label: Text(kycLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kycColor,
                  side: BorderSide(color: kycColor),
                  backgroundColor: kycBg,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: MyShopSpacing.sm),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: ProfileReadOnlyNote(),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── 4. Verification banner ──
            if (!isVerified)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child:
                    _VerificationBanner(verificationStatus: verificationStatus),
              ),
            if (!isVerified) const SizedBox(height: MyShopSpacing.lg),

            // ── 5. Performance card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _PerformanceCard(
                isDriver: isDriver,
                bookings: todayTrips,
                earnings: todayEarnings,
                rating: ratingDisplay,
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // ── 6. General Settings ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: SettingsSection(
                title: 'GENERAL SETTINGS',
                children: [
                  SettingsListTile(
                    icon: Icons.shield_outlined,
                    title: 'Documents & Verification',
                    subtitle: 'KYC, Police Check, ID-Cards',
                    trailingChipLabel: !isVerified ? '1 Action' : null,
                    trailingChipColor: MyShopColors.error,
                    onTap: () => context.push('/account/documents'),
                  ),
                  if (isDriver)
                    SettingsListTile(
                      icon: Icons.directions_car,
                      title: 'Vehicle Information',
                      subtitle: vehicleSubtitle,
                      onTap: () => context.push('/account/vehicle'),
                    )
                  else
                    SettingsListTile(
                      icon: Icons.business_center_outlined,
                      title: 'Business Information',
                      subtitle: user?.businessName ??
                          user?.displayName ??
                          'Not set up yet',
                      onTap: () => context.push('/account/business'),
                    ),
                  SettingsListTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Payout Methods',
                    subtitle: payoutSubtitle,
                    onTap: () => context.push('/account/payouts'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // ── 7. App & Security ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: SettingsSection(
                title: 'APP & SECURITY',
                children: [
                  SettingsListTile(
                    icon: Icons.notifications_outlined,
                    title: 'Notifications',
                    subtitle: 'Push, SMS, and Email',
                    onTap: () => context.push('/account/notifications'),
                  ),
                  SettingsListTile(
                    icon: Icons.lock_outline,
                    title: 'Privacy & Security',
                    subtitle: '2FA, Data Masking',
                    onTap: () => context.push('/account/privacy'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // ── 8. Support ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: SettingsSection(
                title: 'SUPPORT',
                children: [
                  SettingsListTile(
                    icon: Icons.help_outline,
                    title: 'Support & Legal',
                    subtitle: 'Help Center, Terms, Privacy',
                    onTap: () => context.push('/account/support'),
                  ),
                  SettingsListTile(
                    icon: Icons.logout,
                    title: 'Log Out',
                    subtitle: 'Sign out of your account',
                    onTap: () => _showLogoutDialog(context, ref),
                  ),
                  SettingsListTile(
                    icon: Icons.no_accounts_outlined,
                    title: 'Deactivate Account',
                    subtitle: '',
                    danger: true,
                    onTap: () => context.push('/account/deactivate'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // ── 9. Compliance Summary ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _ComplianceSummary(
                kycStatus: kycStatus,
                policeCheckStatus: policeCheckStatus,
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Continue verification CTA ──
            if (!isVerified)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
                child: ElevatedButton(
                  onPressed: () => context.push('/account/documents'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyShopColors.darkSlate,
                    foregroundColor: MyShopColors.textOnPrimary,
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    textStyle: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                  child: const Text('Continue Verification'),
                ),
              ),
            const SizedBox(height: MyShopSpacing.lg),

            // ── App version footer ──
            Center(
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Image.asset(
                    'assets/images/myshop_provider_logo.png',
                    width: 16,
                    height: 16,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(width: 6),
                  const Text('MyShop Provider App',
                      style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary)),
                ]),
                const SizedBox(height: 4),
                Text('Version 1.0.0',
                    style: MyShopTypography.caption.copyWith(fontSize: 10)),
                Text('© 2026 Gilmore Tech. All Rights Reserved.',
                    style: MyShopTypography.caption.copyWith(fontSize: 10)),
                const SizedBox(height: 4),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('Data Policy',
                      style: MyShopTypography.caption.copyWith(
                          fontSize: 10,
                          color: MyShopColors.primaryGold,
                          decoration: TextDecoration.underline)),
                  Text('  •  ', style: MyShopTypography.caption),
                  Text('Compliance',
                      style: MyShopTypography.caption.copyWith(
                          fontSize: 10,
                          color: MyShopColors.primaryGold,
                          decoration: TextDecoration.underline)),
                ]),
              ]),
            ),
            const SizedBox(height: MyShopSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

// ─── Identity card ──────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.isDriver,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.verificationStatus,
    this.photoUrl,
    this.localPhoto,
  });
  final bool isDriver;
  final String fullName;
  final String phone;
  final String email;
  final String verificationStatus;
  final String? photoUrl;
  final File? localPhoto;

  @override
  Widget build(BuildContext context) {
    final isVerified = verificationStatus == 'approved';
    final statusLabel = _capitalize(verificationStatus);
    final statusColor =
        isVerified ? MyShopColors.success : MyShopColors.warning;
    final statusIcon =
        isVerified ? Icons.check_circle_outline : Icons.error_outline;

    final ImageProvider? avatarImage = localPhoto != null
        ? FileImage(localPhoto!)
        : photoUrl != null
            ? NetworkImage(photoUrl!)
            : null;

    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: const Color(0xFFFCEAE1),
          backgroundImage: avatarImage,
          child: avatarImage == null
              ? const Icon(Icons.person,
                  size: 32, color: MyShopColors.textSecondary)
              : null,
        ),
        const SizedBox(width: MyShopSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(fullName,
                  style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textPrimary)),
              Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: MyShopColors.darkSlate,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isDriver ? 'DRIVER' : 'ARTISAN',
                    style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(statusIcon, size: 12, color: statusColor),
                const SizedBox(width: 2),
                Text('$statusLabel Verification',
                    style: MyShopTypography.caption
                        .copyWith(color: statusColor, fontSize: 10)),
              ]),
              const SizedBox(height: 4),
              if (phone.isNotEmpty)
                Text(_maskPhone(phone),
                    style: MyShopTypography.body2.copyWith(fontSize: 12)),
              if (email.isNotEmpty)
                Text(email,
                    style: MyShopTypography.body2.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  /// Mask phone: +233541234567 → +233 ••• 4567
  static String _maskPhone(String phone) {
    if (phone.length < 6) return phone;
    final last4 = phone.substring(phone.length - 4);
    final prefix = phone.substring(0, phone.length > 10 ? 4 : 3);
    return '$prefix ••• $last4';
  }
}

// ─── Verification banner ────────────────────────────────────────────────────

class _VerificationBanner extends StatelessWidget {
  const _VerificationBanner({required this.verificationStatus});
  final String verificationStatus;

  @override
  Widget build(BuildContext context) {
    final isPending = verificationStatus == 'pending';
    final statusText = isPending
        ? 'Your documents are awaiting review. Please complete any remaining steps.'
        : 'Your KYC and Police Check are currently being reviewed. Results are expected within 24-48 hours.';
    final title =
        isPending ? 'Verification Required' : 'Verification in Progress';

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.warning.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.access_time, size: 22, color: MyShopColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
                const SizedBox(height: 2),
                Text(statusText,
                    style: MyShopTypography.body2
                        .copyWith(fontSize: 11, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Performance card ───────────────────────────────────────────────────────

class _PerformanceCard extends StatelessWidget {
  const _PerformanceCard({
    required this.isDriver,
    required this.bookings,
    required this.earnings,
    required this.rating,
  });
  final bool isDriver;
  final String bookings;
  final String earnings;
  final String rating;

  @override
  Widget build(BuildContext context) {
    // Drivers do trips; artisans do jobs. Pair the label with a matching
    // icon so the card reads correctly on each role's account screen.
    final bookingsLabel = isDriver ? 'Trips Today' : 'Jobs Today';
    final bookingsIcon =
        isDriver ? Icons.directions_car_outlined : Icons.handyman_outlined;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('PERFORMANCE',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textSecondary,
                    letterSpacing: 1.0)),
            Text('View History',
                style: MyShopTypography.body2.copyWith(
                    fontSize: 11,
                    color: MyShopColors.primaryGold,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: MyShopSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: MyShopSpacing.md, vertical: MyShopSpacing.md),
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _PerfStat(
                  icon: bookingsIcon, value: bookings, label: bookingsLabel),
              const _PerfDivider(),
              _PerfStat(
                  icon: Icons.payments_outlined,
                  value: earnings,
                  label: 'Earnings'),
              const _PerfDivider(),
              _PerfStat(
                  icon: Icons.star_border, value: rating, label: 'Avg Rating'),
            ],
          ),
        ),
      ],
    );
  }
}

class _PerfStat extends StatelessWidget {
  const _PerfStat(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(children: [
        Icon(icon, size: 16, color: MyShopColors.textSecondary),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textPrimary)),
        Text(label, style: MyShopTypography.caption.copyWith(fontSize: 10)),
      ]),
    );
  }
}

class _PerfDivider extends StatelessWidget {
  const _PerfDivider();
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 36, color: MyShopColors.divider);
  }
}

// ─── Compliance Summary ─────────────────────────────────────────────────────

class _ComplianceSummary extends StatelessWidget {
  const _ComplianceSummary({
    required this.kycStatus,
    required this.policeCheckStatus,
  });
  final String kycStatus;
  final String policeCheckStatus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('COMPLIANCE SUMMARY',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textSecondary,
                letterSpacing: 1.0)),
        const SizedBox(height: MyShopSpacing.sm),
        Container(
          padding: const EdgeInsets.all(MyShopSpacing.md),
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.shield_outlined,
                    size: 16, color: MyShopColors.textSecondary),
                const SizedBox(width: 6),
                const Text('Verification Details',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
              ]),
              const SizedBox(height: MyShopSpacing.sm),
              _ComplianceRow(
                icon: Icons.fingerprint,
                title: 'KYC Identity',
                subtitle: 'Smile Identity Verification',
                status: kycStatus.toUpperCase(),
                statusColor: _statusColor(kycStatus),
                statusBg: _statusBg(kycStatus),
              ),
              const SizedBox(height: 8),
              _ComplianceRow(
                icon: Icons.local_police_outlined,
                title: 'Police Background',
                subtitle: 'Ghana Police Service Check',
                status: policeCheckStatus.toUpperCase(),
                statusColor: _statusColor(policeCheckStatus),
                statusBg: _statusBg(policeCheckStatus),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Color _statusColor(String status) {
    return switch (status) {
      'approved' => MyShopColors.success,
      'rejected' => MyShopColors.error,
      _ => MyShopColors.warning,
    };
  }

  static Color _statusBg(String status) {
    return switch (status) {
      'approved' => MyShopColors.successLight,
      'rejected' => MyShopColors.errorLight,
      _ => MyShopColors.warningLight,
    };
  }
}

class _ComplianceRow extends StatelessWidget {
  const _ComplianceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    required this.statusBg,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;
  final Color statusBg;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: statusColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary)),
              Text(subtitle,
                  style: MyShopTypography.caption.copyWith(fontSize: 10)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusBg,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(status,
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: statusColor)),
        ),
      ]),
    );
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

String _formatGhs(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble()) {
    return ghs.toStringAsFixed(0);
  }
  return ghs.toStringAsFixed(2);
}
