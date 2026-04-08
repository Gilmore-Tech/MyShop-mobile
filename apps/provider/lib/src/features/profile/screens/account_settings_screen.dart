import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/provider_type_provider.dart';
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
///   4. Performance card (Active Trips, Earnings, Rating)
///   5. General Settings section
///   6. App & Security section
///   7. Support section
///   8. Deactivate Account
///   9. Compliance Summary card
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerType = ref.watch(providerTypeProvider);
    final isDriver = providerType.isDriver;

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
              child: _IdentityCard(isDriver: isDriver),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── 3. Action buttons row ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push('/account/edit'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyShopColors.textPrimary,
                        side: const BorderSide(color: MyShopColors.divider),
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Edit Profile'),
                    ),
                  ),
                  const SizedBox(width: MyShopSpacing.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/account/documents'),
                      icon: const Icon(Icons.shield_outlined, size: 14),
                      label: const Text('KYC: Pending'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MyShopColors.warning,
                        side: const BorderSide(color: MyShopColors.warning),
                        backgroundColor: MyShopColors.warningLight,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── 4. Verification banner ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _VerificationBanner(),
            ),
            const SizedBox(height: MyShopSpacing.lg),

            // ── 5. Performance card ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
              child: _PerformanceCard(),
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
                    trailingChipLabel: '1 Action',
                    trailingChipColor: MyShopColors.error,
                    onTap: () => context.push('/account/documents'),
                  ),
                  if (isDriver)
                    SettingsListTile(
                      icon: Icons.directions_car,
                      title: 'Vehicle Information',
                      subtitle: 'Toyota Corolla (GS-2323-22)',
                      onTap: () => context.push('/account/vehicle'),
                    )
                  else
                    SettingsListTile(
                      icon: Icons.business_center_outlined,
                      title: 'Business Information',
                      subtitle: 'Yaakvi Electricals',
                      onTap: () => context.push('/account/business'),
                    ),
                  SettingsListTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Payout Methods',
                    subtitle: 'MoMo: 054 ••• 8821',
                    onTap: () => context.push('/account/payouts'),
                  ),
                  SettingsListTile(
                    icon: Icons.access_time,
                    title: 'Availability & Schedule',
                    subtitle: 'Active • 08:00 - 18:00',
                    onTap: () => context.push('/account/availability'),
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
                  SettingsListTile(
                    icon: Icons.smartphone,
                    title: 'Connected Accounts',
                    subtitle: 'USSD & Adesel Status',
                    trailingChipLabel: 'Online',
                    trailingChipColor: MyShopColors.success,
                    onTap: () {},
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
              child: _ComplianceSummary(),
            ),
            const SizedBox(height: MyShopSpacing.md),

            // ── Continue verification CTA ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
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
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: MyShopColors.primaryGold,
                      borderRadius: BorderRadius.circular(4),
                    ),
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
                Text('Version 2.4.1 (Build 8820)',
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
  const _IdentityCard({required this.isDriver});
  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 32,
          backgroundColor: Color(0xFFFCEAE1),
          child: Icon(Icons.person, size: 32, color: MyShopColors.textSecondary),
        ),
        const SizedBox(width: MyShopSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Kofi Mensah',
                    style: TextStyle(
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
                const Icon(Icons.error_outline,
                    size: 12, color: MyShopColors.warning),
                const SizedBox(width: 2),
                Text('Pending Verification',
                    style: MyShopTypography.caption
                        .copyWith(color: MyShopColors.warning, fontSize: 10)),
              ]),
              const SizedBox(height: 4),
              Text('+233 ••• 4582',
                  style: MyShopTypography.body2.copyWith(fontSize: 12)),
              Text('k.mensah@provider-mail.com',
                  style: MyShopTypography.body2.copyWith(fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Verification banner ────────────────────────────────────────────────────

class _VerificationBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
          const Icon(Icons.access_time,
              size: 22, color: MyShopColors.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Verification in Progress',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                    'Your KYC and Police Check are currently being reviewed. Results are expected within 24-48 hours.',
                    style:
                        MyShopTypography.body2.copyWith(fontSize: 11, height: 1.4)),
                const SizedBox(height: 6),
                Row(children: [
                  Text('Started: Jan 24, 2024',
                      style: MyShopTypography.caption.copyWith(fontSize: 10)),
                  const Spacer(),
                  Text('View Status Details',
                      style: MyShopTypography.body2.copyWith(
                          fontSize: 11,
                          color: MyShopColors.warning,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline)),
                ]),
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
  @override
  Widget build(BuildContext context) {
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
          child: const Row(
            children: [
              _PerfStat(
                  icon: Icons.shopping_bag_outlined,
                  value: '12',
                  label: 'Active Trips'),
              _PerfDivider(),
              _PerfStat(
                  icon: Icons.payments_outlined,
                  value: '450.00',
                  label: 'Earnings'),
              _PerfDivider(),
              _PerfStat(
                  icon: Icons.star_border, value: '4.92', label: 'Avg Rating'),
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
                const Spacer(),
                Text('Last check: 12 Jan, 10:45 AM',
                    style: MyShopTypography.caption.copyWith(fontSize: 9)),
              ]),
              const SizedBox(height: MyShopSpacing.sm),
              _ComplianceRow(
                icon: Icons.fingerprint,
                title: 'KYC Identity',
                subtitle: 'Smile Identity Verification',
                status: 'PENDING',
                statusColor: MyShopColors.warning,
                statusBg: MyShopColors.warningLight,
              ),
              const SizedBox(height: 8),
              _ComplianceRow(
                icon: Icons.local_police_outlined,
                title: 'Police Background',
                subtitle: 'Ghana Police Service Check',
                status: 'APPROVED',
                statusColor: MyShopColors.success,
                statusBg: MyShopColors.successLight,
              ),
            ],
          ),
        ),
      ],
    );
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
