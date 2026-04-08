import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Profile screen — driver identity card, KYC, vehicle, documents, ops chat,
/// dispute, quick links.
///
/// Figma: node 219:13295
/// PRD Reference: PRD 5.4
class EditProviderProfileScreen extends StatelessWidget {
  const EditProviderProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Align(
          alignment: Alignment.centerLeft,
          child: Text('Profile',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary)),
        ),
        titleSpacing: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: MyShopSpacing.md),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 12, color: MyShopColors.textSecondary),
                  const SizedBox(width: 4),
                  Text('KYC OK',
                      style: TextStyle(
                          fontFamily: 'Raleway',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textSecondary,
                          letterSpacing: 0.4)),
                ],
              ),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(0.5),
          child: Divider(
              height: 0.5, thickness: 0.5, color: MyShopColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        children: [
          // ── 1. Identity card with dark slate accent ──
          _IdentityCard(),
          const SizedBox(height: MyShopSpacing.lg),

          // ── 2. Verification status ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('VERIFICATION STATUS',
                  style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: MyShopColors.textSecondary,
                      letterSpacing: 1.0)),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('Update Info',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(
              children: [
                _VerificationRow(
                  icon: Icons.shield_outlined,
                  title: 'SMILE IDENTITY KYC',
                  status: 'Verified',
                  detail: 'Last updated: 12 Oct 2023',
                ),
                const Divider(
                    height: 1,
                    thickness: 0.5,
                    color: MyShopColors.divider,
                    indent: 16,
                    endIndent: 16),
                _VerificationRow(
                  icon: Icons.balance,
                  title: 'POLICE BACKGROUND CHECK',
                  status: 'Completed',
                  detail: 'Cleared on: 05 Jan 2024',
                ),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── 3. Vehicle Details ──
          const Text('VEHICLE DETAILS',
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
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.directions_car_outlined,
                        size: 18, color: MyShopColors.darkSlate),
                    const SizedBox(width: 8),
                    const Text('Toyota Vitz 2018',
                        style: TextStyle(
                            fontFamily: 'Raleway',
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: MyShopColors.textPrimary)),
                  ]),
                  const SizedBox(height: 12),
                  _VehicleDetail(label: 'License Plate', value: 'AS-4432-18'),
                  _VehicleDetail(label: 'Color', value: 'Silver Metallic'),
                  _VehicleDetail(
                      label: 'Insurance', value: 'Comprehensive (Active)'),
                ]),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── 4. Managed Documents ──
          const Text('MANAGED DOCUMENTS',
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
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(
              children: [
                _DocumentRow(
                  title: "Driver's License (Class B)",
                  expiry: 'Expires: 22 Nov 2027',
                  status: 'Verified',
                  statusBg: MyShopColors.darkSlate,
                  statusFg: MyShopColors.textOnDarkSlate,
                ),
                const SizedBox(height: 8),
                _DocumentRow(
                  title: 'Roadworthy Certificate',
                  expiry: 'Expires: 15 Mar 2027',
                  status: 'Verified',
                  statusBg: MyShopColors.darkSlate,
                  statusFg: MyShopColors.textOnDarkSlate,
                ),
                const SizedBox(height: 8),
                _DocumentRow(
                  title: 'Hackney Permit',
                  expiry: 'Expires: 10 Feb 2027',
                  status: 'Reviewing',
                  statusBg: MyShopColors.surfaceWhite,
                  statusFg: MyShopColors.textPrimary,
                  border: true,
                ),
                const SizedBox(height: MyShopSpacing.md),
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyShopColors.darkSlate,
                    foregroundColor: MyShopColors.textOnPrimary,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('Upload New Document'),
                      SizedBox(width: 6),
                      Icon(Icons.chevron_right, size: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── 5. Operations Chat ──
          const Text('OPERATIONS CHAT',
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
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(
              children: [
                Row(children: [
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFFFCEAE1),
                    child: Icon(Icons.support_agent,
                        size: 18, color: MyShopColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Ops Support (Adwoa)',
                                  style: TextStyle(
                                      fontFamily: 'Raleway',
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: MyShopColors.textPrimary)),
                              const Spacer(),
                              Text('14:20',
                                  style: MyShopTypography.caption
                                      .copyWith(fontSize: 10)),
                              const SizedBox(width: 6),
                              Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: MyShopColors.primaryGold,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Text('1',
                                      style: TextStyle(
                                          fontFamily: 'Raleway',
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                              '"Kofi, your payout for trip #8821 has been...',
                              style: MyShopTypography.body2.copyWith(
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                        ]),
                  ),
                ]),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.chat_bubble_outline, size: 16),
                  label: const Text('Open Support Thread'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyShopColors.primaryGold,
                    foregroundColor: MyShopColors.textOnPrimary,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── 6. Dispute card ──
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.errorLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: MyShopColors.surfaceWhite,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: MyShopColors.error.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.error_outline,
                      size: 18, color: MyShopColors.error),
                ),
                const SizedBox(height: 8),
                const Text('Need to report a dispute?',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.error)),
                const SizedBox(height: 4),
                Text(
                    'If you have issues with a recent fare, passenger\nbehavior, or technical glitch, our dispute team is\nready.',
                    textAlign: TextAlign.center,
                    style: MyShopTypography.body2
                        .copyWith(fontSize: 11, height: 1.5)),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.balance, size: 16),
                  label: const Text('Initiate New Dispute'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MyShopColors.error,
                    side: const BorderSide(color: MyShopColors.error),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 13,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // ── 7. Quick links ──
          Row(children: [
            Expanded(
                child: _QuickLink(
                    icon: Icons.help_outline, label: 'HELP CENTER')),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
                child: _QuickLink(
                    icon: Icons.open_in_new, label: 'LEGAL & TERMS')),
          ]),
          const SizedBox(height: MyShopSpacing.xxl),
        ],
      ),
    );
  }
}

// ─── Identity Card ──────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MyShopColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Dark slate top accent
          Container(height: 6, color: MyShopColors.darkSlate),
          Padding(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            child: Column(
              children: [
                // Avatar + name + rating row
                Row(
                  children: [
                    Stack(
                      children: [
                        const CircleAvatar(
                          radius: 32,
                          backgroundColor: Color(0xFFFCEAE1),
                          child: Icon(Icons.person,
                              size: 32, color: MyShopColors.textSecondary),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: MyShopColors.online,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: MyShopColors.surfaceWhite, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: MyShopSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Kofi Mensah',
                              style: TextStyle(
                                  fontFamily: 'Raleway',
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: MyShopColors.textPrimary)),
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.star,
                                size: 16, color: MyShopColors.ratingStar),
                            const SizedBox(width: 4),
                            const Text('4.85',
                                style: TextStyle(
                                    fontFamily: 'Raleway',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: MyShopColors.primaryGold)),
                            const SizedBox(width: 4),
                            Text('(248 trips)',
                                style: MyShopTypography.body2
                                    .copyWith(fontSize: 12)),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MyShopSpacing.md),
                // EARNINGS / LEVEL badges
                Row(children: [
                  Expanded(
                      child: _StatBadge(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'EARNINGS',
                          value: 'GH₵ 1,240.50')),
                  const SizedBox(width: MyShopSpacing.sm),
                  Expanded(
                      child: _StatBadge(
                          icon: Icons.workspace_premium_outlined,
                          label: 'LEVEL',
                          value: 'Gold Partner')),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 12, color: MyShopColors.textSecondary),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 6),
        Text(value,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: MyShopColors.textPrimary)),
      ]),
    );
  }
}

// ─── Verification Row ───────────────────────────────────────────────────────

class _VerificationRow extends StatelessWidget {
  const _VerificationRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.detail,
  });
  final IconData icon;
  final String title;
  final String status;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                Icon(icon, size: 18, color: MyShopColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textSecondary,
                        letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(status,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.textPrimary)),
                Text(detail,
                    style: MyShopTypography.body2.copyWith(
                        fontSize: 11,
                        color: MyShopColors.primaryGold,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              shape: BoxShape.circle,
              border: Border.all(color: MyShopColors.divider),
            ),
            child: const Icon(Icons.check,
                size: 14, color: MyShopColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ─── Vehicle Detail row ─────────────────────────────────────────────────────

class _VehicleDetail extends StatelessWidget {
  const _VehicleDetail({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: MyShopTypography.body2.copyWith(
                  fontSize: 13, color: MyShopColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary)),
        ],
      ),
    );
  }
}

// ─── Document Row ───────────────────────────────────────────────────────────

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.title,
    required this.expiry,
    required this.status,
    required this.statusBg,
    required this.statusFg,
    this.border = false,
  });
  final String title;
  final String expiry;
  final String status;
  final Color statusBg;
  final Color statusFg;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: MyShopSpacing.md, vertical: 12),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.description_outlined,
                size: 18, color: MyShopColors.textSecondary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: MyShopColors.textPrimary)),
                Text(expiry,
                    style: MyShopTypography.body2.copyWith(
                        fontSize: 11,
                        color: MyShopColors.primaryGold,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusBg,
              borderRadius: BorderRadius.circular(12),
              border: border
                  ? Border.all(color: MyShopColors.divider)
                  : null,
            ),
            child: Text(status,
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusFg)),
          ),
        ],
      ),
    );
  }
}

// ─── Quick link tile ────────────────────────────────────────────────────────

class _QuickLink extends StatelessWidget {
  const _QuickLink({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          Icon(icon, size: 22, color: MyShopColors.textPrimary),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textPrimary,
                  letterSpacing: 0.6)),
        ],
      ),
    );
  }
}
