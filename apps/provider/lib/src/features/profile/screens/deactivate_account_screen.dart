import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// Deactivate Account confirmation screen — explains consequences, surfaces
/// blocking status checks, and offers Continue / Keep My Account actions.
///
/// PRD Reference: PRD 5.5 — provider account closure flow.
class DeactivateAccountScreen extends StatelessWidget {
  const DeactivateAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                ),
                children: [
                  const _WarningHero(),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionLabel(text: 'CONSEQUENCES OF DEACTIVATION'),
                  const SizedBox(height: MyShopSpacing.sm),
                  _ConsequencesCard(),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionLabel(text: 'STATUS CHECKS'),
                  const SizedBox(height: MyShopSpacing.sm),
                  const _PendingPayoutsCard(amount: 'GHS 420.50'),
                  const SizedBox(height: MyShopSpacing.md),
                  const _DataRetentionNote(),
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
            _Footer(
              onContinue: () {},
              onKeep: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          Text(
            'Deactivate Account',
            style: MyShopTypography.h1.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Warning hero
// ─────────────────────────────────────────────────────────────────────────────

class _WarningHero extends StatelessWidget {
  const _WarningHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: MyShopColors.errorLight,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.warning_amber_rounded,
            size: 44,
            color: MyShopColors.error,
          ),
        ),
        const SizedBox(height: MyShopSpacing.md),
        Text(
          'Are you sure?',
          style: MyShopTypography.h1.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: MyShopSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.lg),
          child: Text(
            'This will permanently disable your provider profile and remove your access.',
            textAlign: TextAlign.center,
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MyShopTypography.overline.copyWith(
        color: MyShopColors.textSecondary,
        fontWeight: FontWeight.w900,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Consequences card
// ─────────────────────────────────────────────────────────────────────────────

class _ConsequencesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      _Consequence(
        icon: Icons.history,
        title: 'Loss of Work History',
        body:
            'Your track record of 450+ completed jobs will be permanently deleted.',
      ),
      _Consequence(
        icon: Icons.star_border,
        title: 'Reputation Wipe',
        body:
            'Your 4.9-star rating and all 128 verified customer reviews will disappear.',
      ),
      _Consequence(
        icon: Icons.gpp_maybe_outlined,
        title: 'Verification Status',
        body:
            'Your KYC and Police Clearance status will be revoked. Re-applying requires full fees.',
      ),
      _Consequence(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Financial History',
        body:
            'You will lose access to your historical earnings reports and tax documents.',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _ConsequenceRow(item: items[i]),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: MyShopSpacing.md,
                endIndent: MyShopSpacing.md,
                color: MyShopColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _Consequence {
  const _Consequence({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _ConsequenceRow extends StatelessWidget {
  const _ConsequenceRow({required this.item});

  final _Consequence item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceGrey,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(item.icon, size: 20, color: MyShopColors.textPrimary),
          ),
          const SizedBox(width: MyShopSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: MyShopTypography.body2.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending payouts card
// ─────────────────────────────────────────────────────────────────────────────

class _PendingPayoutsCard extends StatelessWidget {
  const _PendingPayoutsCard({required this.amount});

  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          top: BorderSide(color: MyShopColors.primaryGold, width: 3),
        ),
      ),
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.error_outline,
                size: 18,
                color: MyShopColors.primaryGold,
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Text(
                'Action Required: Pending Payouts',
                style: MyShopTypography.h3.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: MyShopTypography.body2.copyWith(height: 1.5),
                    children: [
                      const TextSpan(text: 'You have '),
                      TextSpan(
                        text: amount,
                        style: const TextStyle(
                          color: MyShopColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(
                        text:
                            ' in your wallet. Deactivating now will freeze these funds. Please withdraw first.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                GestureDetector(
                  onTap: () {},
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Go to Payouts',
                        style: MyShopTypography.body1.copyWith(
                          color: MyShopColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward,
                        size: 16,
                        color: MyShopColors.textPrimary,
                      ),
                    ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Data retention note
// ─────────────────────────────────────────────────────────────────────────────

class _DataRetentionNote extends StatelessWidget {
  const _DataRetentionNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              'Data retention policy: We retain certain financial records for up to 7 years to comply with Ghanaian tax laws and regulatory audit requirements.',
              style: MyShopTypography.body2.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky footer
// ─────────────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.onContinue, required this.onKeep});

  final VoidCallback onContinue;
  final VoidCallback onKeep;

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
          GestureDetector(
            onTap: onContinue,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: MyShopColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                'Understand & Continue',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.textOnPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          GestureDetector(
            onTap: onKeep,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MyShopColors.divider),
              ),
              alignment: Alignment.center,
              child: Text(
                'Keep My Account',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.textPrimary,
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
