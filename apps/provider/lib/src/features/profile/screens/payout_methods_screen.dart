import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Payout Methods screen — MoMo + bank accounts, payout history, schedule.
///
/// Figma: node 313:27042
class PayoutMethodsScreen extends StatelessWidget {
  const PayoutMethodsScreen({super.key});

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
        padding: const EdgeInsets.fromLTRB(
            MyShopSpacing.md, MyShopSpacing.md, MyShopSpacing.md, MyShopSpacing.lg),
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
                              fontSize: 13,
                              color: MyShopColors.textSecondary)),
                      const SizedBox(height: 6),
                      const Text('₵2,450.00',
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
                    size: 14, color: MyShopColors.primaryGold),
                const SizedBox(width: 6),
                Text.rich(
                  TextSpan(
                    style: MyShopTypography.body2.copyWith(
                        fontSize: 12, color: MyShopColors.textSecondary),
                    children: const [
                      TextSpan(text: 'Last Payout: '),
                      TextSpan(
                          text: 'Jan 12',
                          style: TextStyle(
                              color: MyShopColors.primaryGold,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const Spacer(),
                const Text('₵1,820.00',
                    style: TextStyle(
                        fontFamily: 'Raleway',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: MyShopColors.textPrimary)),
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

          // MoMo accounts
          Row(children: [
            const Text('MOBILE MONEY ACCOUNTS',
                style: TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: MyShopColors.textSecondary,
                    letterSpacing: 1.0)),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MyShopColors.divider),
              ),
              child: Text('MTN & Telecel',
                  style: MyShopTypography.body2.copyWith(
                      fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: MyShopSpacing.sm),
          const _MomoCard(
            provider: 'MTN GHANA',
            name: 'Samuel K. Boateng',
            number: '**** **** 0244',
            isPrimary: true,
            verified: true,
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // Bank accounts
          const Text('BANK ACCOUNTS',
              style: TextStyle(
                  fontFamily: 'Raleway',
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: MyShopColors.textSecondary,
                  letterSpacing: 1.0)),
          const SizedBox(height: MyShopSpacing.sm),
          const _BankCard(
            bank: 'STANDARD CHARTERED',
            name: 'S. K. Boateng',
            number: '**** **** 8821',
            status: 'pending',
          ),
          const SizedBox(height: MyShopSpacing.sm),
          DottedCta(
            icon: Icons.add,
            label: 'Add New Bank Account',
            onTap: () {},
          ),
          const SizedBox(height: MyShopSpacing.lg),

          // Recent payout history
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
              const SizedBox(height: MyShopSpacing.md),
              const _PayoutHistory(
                  date: 'Payout to MoMo',
                  subtitle: 'Jan 15, 2024',
                  amount: '₵450.00',
                  status: 'Completed'),
              const Divider(height: 20, color: MyShopColors.divider),
              const _PayoutHistory(
                  date: 'Payout to MoMo',
                  subtitle: 'Jan 10, 2024',
                  amount: '₵1,200.00',
                  status: 'Completed'),
              const Divider(height: 20, color: MyShopColors.divider),
              const _PayoutHistory(
                  date: 'Payout to MoMo',
                  subtitle: 'Dec 28, 2023',
                  amount: '₵890.00',
                  status: 'Completed'),
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
                      text:
                          'Need help managing your payouts? Contact our '),
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
              'Version 2.4.1 (Stable)  •  © 2026 MyShop Provider App',
              style: MyShopTypography.caption.copyWith(
                  fontSize: 10, color: MyShopColors.textSecondary),
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
  });
  final String provider;
  final String name;
  final String number;
  final bool isPrimary;
  final bool verified;

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
          const Icon(Icons.more_vert,
              size: 20, color: MyShopColors.textSecondary),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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

class _BankCard extends StatelessWidget {
  const _BankCard({
    required this.bank,
    required this.name,
    required this.number,
    required this.status,
  });
  final String bank;
  final String name;
  final String number;
  final String status;

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
              child: const Icon(Icons.account_balance,
                  size: 22, color: MyShopColors.darkSlate)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(bank,
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
          const Icon(Icons.more_vert,
              size: 20, color: MyShopColors.textSecondary),
        ]),
        const SizedBox(height: MyShopSpacing.sm),
        Row(children: [
          const SizedBox(width: 56),
          Expanded(
            child: Text(number,
                style: MyShopTypography.body2.copyWith(
                    fontSize: 13, color: MyShopColors.textSecondary)),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: MyShopTypography.body2.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textSecondary)),
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
      {super.key,
      required this.child,
      required this.color,
      this.radius = 12});
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
    final rrect = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(radius));
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

class _PayoutHistory extends StatelessWidget {
  const _PayoutHistory({
    required this.date,
    required this.subtitle,
    required this.amount,
    required this.status,
  });
  final String date;
  final String subtitle;
  final String amount;
  final String status;
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.history,
            size: 16, color: MyShopColors.textSecondary),
      ),
      const SizedBox(width: 12),
      Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(date,
                style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary)),
            const SizedBox(height: 2),
            Text(subtitle,
                style: MyShopTypography.caption.copyWith(
                    fontSize: 11, color: MyShopColors.textSecondary)),
          ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(amount,
            style: const TextStyle(
                fontFamily: 'Raleway',
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: MyShopColors.textPrimary)),
        const SizedBox(height: 2),
        Text(status,
            style: MyShopTypography.caption.copyWith(
                fontSize: 11,
                color: MyShopColors.success,
                fontWeight: FontWeight.w700)),
      ]),
    ]);
  }
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
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: MyShopColors.textPrimary)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: MyShopTypography.caption.copyWith(
                      fontSize: 11, color: MyShopColors.textSecondary)),
            ])),
        const Icon(Icons.chevron_right,
            size: 20, color: MyShopColors.textSecondary),
      ]),
    );
  }
}
