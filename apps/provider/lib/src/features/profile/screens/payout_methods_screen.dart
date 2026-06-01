import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../providers/provider_type_provider.dart';
import '../widgets/payout_method_sheet.dart';

/// Payout Methods screen — MoMo + bank accounts, payout history, schedule.
///
/// Figma: node 313:27042
class PayoutMethodsScreen extends ConsumerWidget {
  const PayoutMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    // Payout fields are per-role at the schema level (Driver.payoutMethod
    // vs Artisan.payoutMethod). Cross-role fallback bled the Artisan's
    // number onto the Driver dashboard — read ONLY the active role.
    final providerType = ref.watch(providerTypeProvider);
    final dp = user?.driverProfile;
    final ap = user?.artisanProfile;
    final payoutMethod =
        providerType.isDriver ? dp?.payoutMethod : ap?.payoutMethod;
    final payoutAccount = providerType.isDriver
        ? dp?.payoutAccountNumber
        : ap?.payoutAccountNumber;
    final hasPayoutMethod = payoutMethod != null && payoutAccount != null;
    // The backend flips this to true once the user verifies their MoMo
    // number via OTP. After that, only an admin can change it.
    final payoutLocked = providerType.isDriver
        ? (dp?.payoutLocked ?? false)
        : (ap?.payoutLocked ?? false);
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Payout Methods',
            style: TextStyle(
                fontFamily: 'Raleway',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary)),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: MyShopColors.divider),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(MyShopSpacing.md, MyShopSpacing.md,
            MyShopSpacing.md, MyShopSpacing.lg),
        children: [
          // Available balance card
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.offWhite,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Available for Payout',
                          style: MyShopTypography.body2.copyWith(
                              fontSize: 13, color: MyShopColors.textSecondary)),
                      const SizedBox(height: 6),
                      const Text('₵0',
                          style: TextStyle(
                              fontFamily: 'Raleway',
                              fontSize: 32,
                              fontWeight: FontWeight.w900,
                              color: MyShopColors.textPrimary,
                              height: 1.1)),
                    ])),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: MyShopColors.darkSlate,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.north_east,
                      size: 22, color: Colors.white),
                ),
              ]),
              const SizedBox(height: MyShopSpacing.md),
              const Divider(height: 1, color: MyShopColors.divider),
              const SizedBox(height: MyShopSpacing.sm),
              Row(children: [
                const Icon(Icons.access_time,
                    size: 14, color: MyShopColors.textSecondary),
                const SizedBox(width: 6),
                Text('No payouts yet',
                    style: MyShopTypography.body2.copyWith(
                        fontSize: 12, color: MyShopColors.textSecondary)),
              ]),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.shield_outlined,
                size: 14, color: MyShopColors.textSecondary),
            const SizedBox(width: 6),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: MyShopTypography.caption.copyWith(
                      fontSize: 11,
                      color: MyShopColors.textSecondary,
                      height: 1.45),
                  children: const [
                    TextSpan(text: 'Your payments are secured with '),
                    TextSpan(
                        text: 'Bank-Grade Encryption',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: MyShopColors.textPrimary)),
                    TextSpan(text: ' and verified for compliance.'),
                  ],
                ),
              ),
            ),
          ]),
          const SizedBox(height: MyShopSpacing.lg),

          // Payout methods
          const Text('PAYOUT METHODS',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.0)),
          const SizedBox(height: MyShopSpacing.sm),
          if (hasPayoutMethod)
            _MomoCard(
              provider: payoutMethodLabel(payoutMethod),
              name: user?.fullName ?? '',
              number:
                  '**** **** ${payoutAccount.substring(payoutAccount.length > 4 ? payoutAccount.length - 4 : 0)}',
              isPrimary: true,
              verified: payoutLocked,
              // No edit affordance once OTP-verified — only an admin can
              // change the locked payout method.
              onEdit:
                  payoutLocked ? null : () => showPayoutMethodSheet(context),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MyShopColors.divider),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.account_balance_wallet_outlined,
                        size: 20, color: MyShopColors.textSecondary),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Text('No payout method set up',
                      style: MyShopTypography.body1
                          .copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: MyShopSpacing.xs),
                  Text(
                      'Add a MoMo number — we\'ll send a 6-digit code to '
                      'verify it before locking it in.',
                      textAlign: TextAlign.center,
                      style: MyShopTypography.body2
                          .copyWith(color: MyShopColors.textSecondary)),
                ],
              ),
            ),
          const SizedBox(height: MyShopSpacing.sm),
          if (payoutLocked)
            _LockedFooter(
                onContactSupport: () => context.push('/account/support'))
          else
            DottedCta(
              icon: hasPayoutMethod ? Icons.swap_horiz : Icons.add,
              label: hasPayoutMethod
                  ? 'Change Payout Method'
                  : 'Add Payout Method',
              onTap: () => showPayoutMethodSheet(context),
            ),
          const SizedBox(height: MyShopSpacing.lg),

          // Recent payout history — empty state
          Container(
            padding: const EdgeInsets.all(MyShopSpacing.md),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: Column(children: [
              Row(children: [
                const Text('Recent Payout History',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
                const Spacer(),
                Text('View All',
                    style: MyShopTypography.body2.copyWith(
                        fontSize: 12,
                        color: MyShopColors.primaryGold,
                        fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: MyShopSpacing.lg),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.history,
                    size: 20, color: MyShopColors.textSecondary),
              ),
              const SizedBox(height: MyShopSpacing.sm),
              Text('No payouts yet',
                  style: MyShopTypography.body1
                      .copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: MyShopSpacing.xs),
              Text('Your payout history will appear here',
                  style: MyShopTypography.body2
                      .copyWith(color: MyShopColors.textSecondary)),
              const SizedBox(height: MyShopSpacing.md),
            ]),
          ),
          const SizedBox(height: MyShopSpacing.md),

          const _LinkRow(
              icon: Icons.calendar_today_outlined,
              title: 'Payout Schedule',
              subtitle: 'Every Monday morning'),
          const SizedBox(height: MyShopSpacing.sm),
          const _LinkRow(
              icon: Icons.info_outline,
              title: 'Tax Information',
              subtitle: 'GRA compliance certificates'),
          const SizedBox(height: MyShopSpacing.lg),

          Center(
            child: Text.rich(
              TextSpan(
                style: MyShopTypography.caption.copyWith(
                    fontSize: 11,
                    color: MyShopColors.textSecondary,
                    height: 1.5),
                children: const [
                  TextSpan(
                      text: 'Need help managing your payouts? Contact our '),
                  TextSpan(
                      text: 'Financial Support Team',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                          decoration: TextDecoration.underline)),
                  TextSpan(text: ' or visit the '),
                  TextSpan(
                      text: 'Help Center',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: MyShopColors.textPrimary,
                          decoration: TextDecoration.underline)),
                  TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              'Version 1.0.0  •  © 2026 MyShop Provider App',
              style: MyShopTypography.caption
                  .copyWith(fontSize: 10, color: MyShopColors.textSecondary),
            ),
          ),
          const SizedBox(height: MyShopSpacing.lg),
        ],
      ),
    );
  }
}

class _MomoCard extends StatelessWidget {
  const _MomoCard({
    required this.provider,
    required this.name,
    required this.number,
    required this.isPrimary,
    required this.verified,
    this.onEdit,
  });
  final String provider;
  final String name;
  final String number;
  final bool isPrimary;
  final bool verified;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.smartphone,
                  size: 22, color: MyShopColors.darkSlate)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(provider,
                    style: MyShopTypography.overline.copyWith(
                        fontSize: 10,
                        color: MyShopColors.textSecondary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(name,
                    style: const TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: MyShopColors.textPrimary)),
              ])),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: MyShopColors.textSecondary),
            tooltip: 'Edit payout method',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            visualDensity: VisualDensity.compact,
          ),
        ]),
        const SizedBox(height: MyShopSpacing.sm),
        Row(children: [
          const SizedBox(width: 56),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(number,
                    style: MyShopTypography.body2.copyWith(
                        fontSize: 13, color: MyShopColors.textSecondary)),
                if (isPrimary) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.check_circle,
                        size: 14, color: MyShopColors.primaryGold),
                    const SizedBox(width: 4),
                    Text('Primary Payout Method',
                        style: MyShopTypography.caption.copyWith(
                            fontSize: 11,
                            color: MyShopColors.primaryGold,
                            fontWeight: FontWeight.w700)),
                  ]),
                ],
              ],
            ),
          ),
          if (verified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: MyShopColors.successLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Verified',
                  style: MyShopTypography.overline.copyWith(
                      fontSize: 11,
                      color: MyShopColors.success,
                      fontWeight: FontWeight.w700)),
            ),
        ]),
      ]),
    );
  }
}

class DottedCta extends StatelessWidget {
  const DottedCta(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DottedBorder(
        color: MyShopColors.divider,
        radius: 14,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          alignment: Alignment.center,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 18, color: MyShopColors.textPrimary),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary)),
          ]),
        ),
      ),
    );
  }
}

/// Lightweight dashed-border container (avoids extra package dependency).
class DottedBorder extends StatelessWidget {
  const DottedBorder(
      {super.key, required this.child, required this.color, this.radius = 12});
  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRectPainter(color: color, radius: radius),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final rrect =
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final next = (dist + dash).clamp(0, metric.length).toDouble();
        canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) =>
      old.color != color || old.radius != radius;
}

class _LinkRow extends StatelessWidget {
  const _LinkRow(
      {required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(children: [
        Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: MyShopColors.darkSlate)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: MyShopColors.textPrimary)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: MyShopTypography.caption
                  .copyWith(fontSize: 11, color: MyShopColors.textSecondary)),
        ])),
        const Icon(Icons.chevron_right,
            size: 20, color: MyShopColors.textSecondary),
      ]),
    );
  }
}

/// Replaces the "Add / Change" CTA when the payout method is locked.
/// Surfaces the immutability rule and a deep-link to support.
class _LockedFooter extends StatelessWidget {
  const _LockedFooter({required this.onContactSupport});

  final VoidCallback onContactSupport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline,
              size: 18, color: MyShopColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Payout number is locked',
                  style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: MyShopColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'You\'ve already verified your payout number. To change '
                  'it, please contact support with the reason.',
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onContactSupport,
                  child: const Text(
                    'Contact support',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: MyShopColors.primaryGold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
