import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../artisan_home/providers/artisan_earnings_provider.dart';
import '../../auth/providers/current_user_provider.dart';

/// Artisan-side earnings details screen.
///
/// PRD Reference: PRD 5.4 — provider earnings & payouts.
/// Fetches real earnings from GET /payments/earnings?period=today|week|month.
class ArtisanEarningsScreen extends ConsumerStatefulWidget {
  const ArtisanEarningsScreen({super.key});

  @override
  ConsumerState<ArtisanEarningsScreen> createState() =>
      _ArtisanEarningsScreenState();
}

class _ArtisanEarningsScreenState
    extends ConsumerState<ArtisanEarningsScreen> {
  _Period _period = _Period.weekly;

  String get _periodKey {
    switch (_period) {
      case _Period.today:
        return 'today';
      case _Period.weekly:
        return 'week';
      case _Period.monthly:
        return 'month';
    }
  }

  @override
  Widget build(BuildContext context) {
    final earningsAsync =
        ref.watch(artisanEarningsByPeriodProvider(_periodKey));
    final user = ref.watch(currentUserProvider);
    final ap = user?.artisanProfile;

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: earningsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: MyShopColors.primaryGold,
                  ),
                ),
                error: (_, __) => Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: MyShopColors.textSecondary,
                      ),
                      const SizedBox(height: MyShopSpacing.sm),
                      Text(
                        'Could not load earnings',
                        style: MyShopTypography.body1,
                      ),
                      const SizedBox(height: MyShopSpacing.sm),
                      TextButton(
                        onPressed: () => ref.invalidate(
                          artisanEarningsByPeriodProvider(_periodKey),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (earnings) => _EarningsContent(
                  earnings: earnings,
                  period: _period,
                  onPeriodChanged: (p) => setState(() => _period = p),
                  jobsDone: ap?.completedJobsCount ?? 0,
                ),
              ),
            ),
            _PayoutFooter(onTap: () {}),
          ],
        ),
      ),
    );
  }
}

class _EarningsContent extends StatelessWidget {
  const _EarningsContent({
    required this.earnings,
    required this.period,
    required this.onPeriodChanged,
    required this.jobsDone,
  });

  final DriverEarnings earnings;
  final _Period period;
  final ValueChanged<_Period> onPeriodChanged;
  final int jobsDone;

  @override
  Widget build(BuildContext context) {
    // Compute display values from the earnings response
    final totalPesewas = period == _Period.today
        ? earnings.todayAmountPesewas
        : earnings.weekAmountPesewas;
    final totalGhs = totalPesewas / 100;
    // Platform commission is 20% of total
    final commissionGhs = totalGhs * 0.20;
    final netGhs = totalGhs - commissionGhs;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      children: [
        _PeriodSegmented(value: period, onChanged: onPeriodChanged),
        const SizedBox(height: MyShopSpacing.md),
        _BalanceCard(
          available: netGhs,
          totalRevenue: totalGhs,
          jobsDone: jobsDone,
        ),
        const SizedBox(height: MyShopSpacing.md),
        Row(
          children: [
            Expanded(
              child: _MiniStatCard(
                label: 'TRIPS',
                value: earnings.todayTrips.toString(),
                subtitle: 'Today',
              ),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: _MiniStatCard(
                label: 'PLATFORM FEE',
                value: 'GH₵ ${commissionGhs.toStringAsFixed(2)}',
                subtitle: '20% commission',
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.lg),

        // Activity section — empty state until job history endpoint exists
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent Activity',
                style: MyShopTypography.h2.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),
        Container(
          padding: const EdgeInsets.all(MyShopSpacing.lg),
          decoration: BoxDecoration(
            color: MyShopColors.offWhite,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                size: 40,
                color: MyShopColors.textSecondary,
              ),
              const SizedBox(height: MyShopSpacing.sm),
              Text(
                'No activity yet',
                style: MyShopTypography.body1.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Completed jobs will appear here.',
                style: MyShopTypography.body2,
              ),
            ],
          ),
        ),
        const SizedBox(height: MyShopSpacing.lg),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Text(
        'Earnings Details',
        style: MyShopTypography.h1.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 18,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period segmented control
// ---------------------------------------------------------------------------

enum _Period { today, weekly, monthly }

class _PeriodSegmented extends StatelessWidget {
  const _PeriodSegmented({required this.value, required this.onChanged});

  final _Period value;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          _seg('Today', _Period.today),
          _seg('Weekly', _Period.weekly),
          _seg('Monthly', _Period.monthly),
        ],
      ),
    );
  }

  Widget _seg(String label, _Period p) {
    final selected = value == p;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(p),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? MyShopColors.surfaceWhite : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x1A000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: MyShopTypography.body1.copyWith(
              color: selected
                  ? MyShopColors.textPrimary
                  : MyShopColors.textSecondary,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balance card
// ---------------------------------------------------------------------------

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.available,
    required this.totalRevenue,
    required this.jobsDone,
  });

  final double available;
  final double totalRevenue;
  final int jobsDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.lg),
      decoration: BoxDecoration(
        color: MyShopColors.darkSlate,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Net Earnings',
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textOnDarkSlate.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Text(
            'GH₵ ${available.toStringAsFixed(2)}',
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: MyShopColors.textOnDarkSlate,
              height: 1.1,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Divider(
            height: 1,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Row(
            children: [
              Expanded(
                child: _miniStat(
                  label: 'GROSS REVENUE',
                  value: 'GH₵ ${totalRevenue.toStringAsFixed(2)}',
                ),
              ),
              Expanded(
                child: _miniStat(
                  label: 'JOBS DONE',
                  value: jobsDone.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat({required String label, required String value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: MyShopTypography.overline.copyWith(
            color: MyShopColors.primaryGold,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Raleway',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: MyShopColors.textOnDarkSlate,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Mini stat card
// ---------------------------------------------------------------------------

class _MiniStatCard extends StatelessWidget {
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.subtitle,
  });

  final String label;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: MyShopTypography.overline.copyWith(
              color: MyShopColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: MyShopTypography.h2.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: MyShopTypography.body2.copyWith(
              color: MyShopColors.primaryGold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payout footer
// ---------------------------------------------------------------------------

class _PayoutFooter extends StatelessWidget {
  const _PayoutFooter({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md + MediaQuery.of(context).padding.bottom * 0.2,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_outlined,
                size: 16,
                color: MyShopColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Settlement usually takes 2-4 hours',
                  style: MyShopTypography.body2,
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: MyShopColors.darkSlate,
                borderRadius: BorderRadius.circular(28),
              ),
              alignment: Alignment.center,
              child: Text(
                'Request Payout Now',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.textOnDarkSlate,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
