import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.9 — Loyalty points: earned per ride/job, redeemable for ride discounts.
// Tiers: Bronze (0–499), Silver (500–1999), Gold (2000+).
// EDD: GET /v1/users/me/loyalty  → { points, tier, lifetimePoints, ledger[] }

class LoyaltyPointsScreen extends ConsumerWidget {
  const LoyaltyPointsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w    = size.width;
    final h    = size.height;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back,
              color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('Loyalty Points',
            style: TextStyle(
                color:      MyShopColors.textPrimary,
                fontSize:   w * 0.044,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(w * 0.05),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _BalanceCard(w: w, h: h),
            SizedBox(height: h * 0.024),
            _TierProgress(w: w, h: h),
            SizedBox(height: h * 0.028),
            _SectionTitle(text: 'How to earn', w: w),
            SizedBox(height: h * 0.016),
            _EarnGrid(w: w, h: h),
            SizedBox(height: h * 0.028),
            _SectionTitle(text: 'Redeem points', w: w),
            SizedBox(height: h * 0.016),
            _RedeemCard(w: w, h: h),
            SizedBox(height: h * 0.028),
            _SectionTitle(text: 'Recent activity', w: w),
            SizedBox(height: h * 0.016),
            _LedgerList(w: w, h: h),
          ],
        ),
      ),
    );
  }
}

// ── Balance card ───────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final double w, h;
  const _BalanceCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      width:   double.infinity,
      padding: EdgeInsets.all(w * 0.05),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [MyShopColors.primaryGold, MyShopColors.primaryGoldDark],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(w * 0.024),
                decoration: BoxDecoration(
                  color:        Colors.white.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.military_tech_rounded,
                    color: Colors.white, size: w * 0.056),
              ),
              SizedBox(width: w * 0.024),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Silver Member',
                      style: TextStyle(
                        color:      Colors.white,
                        fontSize:   w * 0.034,
                        fontWeight: FontWeight.w600,
                      )),
                  Text('MyShop Loyalty',
                      style: TextStyle(
                          color:    Colors.white.withAlpha(180),
                          fontSize: w * 0.028)),
                ],
              ),
            ],
          ),
          SizedBox(height: h * 0.020),
          Text('720',
              style: TextStyle(
                color:      Colors.white,
                fontSize:   w * 0.100,
                fontWeight: FontWeight.w900,
                height:     1.0,
              )),
          Text('points available',
              style: TextStyle(
                  color:    Colors.white.withAlpha(200),
                  fontSize: w * 0.034)),
          SizedBox(height: h * 0.016),
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.036, vertical: h * 0.012),
            decoration: BoxDecoration(
              color:        Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_offer_rounded,
                    color: Colors.white, size: 16),
                SizedBox(width: w * 0.020),
                Text('Worth GHS 7.20 in ride discounts',
                    style: TextStyle(
                      color:      Colors.white,
                      fontSize:   w * 0.030,
                      fontWeight: FontWeight.w600,
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tier progress ──────────────────────────────────────────────────────────────

class _TierProgress extends StatelessWidget {
  final double w, h;
  const _TierProgress({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    // Silver: 500–1999; currently at 720 → 26.7% through Silver
    const progress = (720 - 500) / (2000 - 500); // ≈ 0.147

    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TierChip(label: 'Bronze', isActive: false, w: w),
              _TierChip(label: 'Silver', isActive: true,  w: w),
              _TierChip(label: 'Gold',   isActive: false, w: w),
            ],
          ),
          SizedBox(height: h * 0.016),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           progress,
              backgroundColor: const Color(0xFFE8EAEC),
              valueColor:      const AlwaysStoppedAnimation<Color>(MyShopColors.primaryGold),
              minHeight:       8,
            ),
          ),
          SizedBox(height: h * 0.010),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('720 pts',
                  style: TextStyle(
                    color:      MyShopColors.textPrimary,
                    fontSize:   w * 0.030,
                    fontWeight: FontWeight.w600,
                  )),
              Text('1,280 pts to Gold',
                  style: TextStyle(
                      color:    MyShopColors.textSecondary,
                      fontSize: w * 0.030)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TierChip extends StatelessWidget {
  final String label;
  final bool   isActive;
  final double w;
  const _TierChip(
      {required this.label, required this.isActive, required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: w * 0.030, vertical: 5),
      decoration: BoxDecoration(
        color:        isActive ? MyShopColors.primaryGoldLight : MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isActive ? MyShopColors.primaryGold : const Color(0xFFE8EAEC)),
      ),
      child: Text(label,
          style: TextStyle(
            color:      isActive ? MyShopColors.primaryGold : MyShopColors.textSecondary,
            fontSize:   w * 0.028,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
          )),
    );
  }
}

// ── Earn grid ──────────────────────────────────────────────────────────────────

class _EarnGrid extends StatelessWidget {
  final double w, h;
  const _EarnGrid({required this.w, required this.h});

  static const _items = [
    (icon: Icons.directions_car_rounded, label: 'Complete a ride',   pts: '+5 pts'),
    (icon: Icons.work_rounded,           label: 'Complete a job',    pts: '+10 pts'),
    (icon: Icons.person_add_rounded,     label: 'Refer a friend',    pts: '+100 pts'),
    (icon: Icons.star_rounded,           label: 'Leave a rating',    pts: '+2 pts'),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount:   2,
      shrinkWrap:       true,
      physics:          const NeverScrollableScrollPhysics(),
      crossAxisSpacing: w * 0.030,
      mainAxisSpacing:  w * 0.030,
      childAspectRatio: 1.6,
      children: _items.map((item) {
        return Container(
          padding: EdgeInsets.all(w * 0.036),
          decoration: BoxDecoration(
            color:        MyShopColors.surfaceWhite,
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: MyShopColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, color: MyShopColors.primaryGold, size: w * 0.052),
              const Spacer(),
              Text(item.pts,
                  style: TextStyle(
                    color:      MyShopColors.primaryGold,
                    fontSize:   w * 0.036,
                    fontWeight: FontWeight.w800,
                  )),
              const SizedBox(height: 2),
              Text(item.label,
                  style: TextStyle(
                      color:    MyShopColors.textSecondary,
                      fontSize: w * 0.028)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Redeem card ────────────────────────────────────────────────────────────────

class _RedeemCard extends StatelessWidget {
  final double w, h;
  const _RedeemCard({required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(w * 0.04),
      decoration: BoxDecoration(
        color:        MyShopColors.successLight,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: MyShopColors.success.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.redeem_rounded, color: MyShopColors.success, size: 22),
              SizedBox(width: w * 0.024),
              Text('Ride Discount',
                  style: TextStyle(
                    color:      MyShopColors.success,
                    fontSize:   w * 0.038,
                    fontWeight: FontWeight.w700,
                  )),
            ],
          ),
          SizedBox(height: h * 0.012),
          Text(
            'Redeem 100 points for GHS 1.00 off your next ride. '
            'Points are applied automatically at checkout.',
            style: TextStyle(
                color:    MyShopColors.success,
                fontSize: w * 0.032,
                height:   1.5),
          ),
          SizedBox(height: h * 0.016),
          SizedBox(
            height: h * 0.054,
            child: ElevatedButton(
              onPressed: () {
                // TODO: POST /v1/loyalty/redeem { amount: 100 }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: MyShopColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text('Redeem 100 pts → GHS 1.00',
                  style: TextStyle(
                      fontSize:   w * 0.034,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Ledger list ────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final double w;
  const _SectionTitle({required this.text, required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          color:      MyShopColors.textPrimary,
          fontSize:   w * 0.040,
          fontWeight: FontWeight.w700,
        ));
  }
}

class _LedgerList extends StatelessWidget {
  final double w, h;
  const _LedgerList({required this.w, required this.h});

  static const _entries = [
    (label: 'Ride completed',      date: 'Today',    pts: '+5',   earn: true),
    (label: 'Referral — Kwesi A.', date: 'Oct 21',   pts: '+100', earn: true),
    (label: 'Job completed',       date: 'Oct 20',   pts: '+10',  earn: true),
    (label: 'Ride discount used',  date: 'Oct 18',   pts: '-100', earn: false),
    (label: 'Left a rating',       date: 'Oct 15',   pts: '+2',   earn: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:        MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: _entries.map((e) {
          final isLast = e == _entries.last;
          return Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: w * 0.04, vertical: h * 0.016),
                child: Row(
                  children: [
                    Container(
                      width:  w * 0.10,
                      height: w * 0.10,
                      decoration: BoxDecoration(
                        color: e.earn ? MyShopColors.primaryGoldLight : MyShopColors.errorLight,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        e.earn
                            ? Icons.add_circle_outline_rounded
                            : Icons.remove_circle_outline_rounded,
                        color: e.earn ? MyShopColors.primaryGold : MyShopColors.error,
                        size: w * 0.048,
                      ),
                    ),
                    SizedBox(width: w * 0.030),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.label,
                              style: TextStyle(
                                color:      MyShopColors.textPrimary,
                                fontSize:   w * 0.036,
                                fontWeight: FontWeight.w600,
                              )),
                          const SizedBox(height: 2),
                          Text(e.date,
                              style: TextStyle(
                                  color:    MyShopColors.textSecondary,
                                  fontSize: w * 0.030)),
                        ],
                      ),
                    ),
                    Text(e.pts,
                        style: TextStyle(
                          color:      e.earn ? MyShopColors.primaryGold : MyShopColors.error,
                          fontSize:   w * 0.038,
                          fontWeight: FontWeight.w800,
                        )),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(
                    height: 1, indent: 16, endIndent: 16,
                    color: MyShopColors.divider),
            ],
          );
        }).toList(),
      ),
    );
  }
}
