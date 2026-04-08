import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// Support & Legal — Help Center search, categories, and legal links.
///
/// PRD Reference: PRD 5.5 — provider help & compliance.
class SupportLegalScreen extends StatelessWidget {
  const SupportLegalScreen({super.key});

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
                  MyShopSpacing.md,
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                ),
                children: [
                  const _SearchBar(),
                  const SizedBox(height: MyShopSpacing.sm),
                  const _CommonlySearched(),
                  const SizedBox(height: MyShopSpacing.lg),
                  Text(
                    'DIRECT HELP',
                    style: MyShopTypography.overline.copyWith(
                      color: MyShopColors.textSecondary,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DirectHelpCard(
                    iconBg: MyShopColors.primaryGold,
                    icon: Icons.chat_bubble_outline,
                    iconColor: MyShopColors.textOnPrimary,
                    title: 'Contact Support',
                    subtitle: 'Typical response time: < 10 mins',
                    background: MyShopColors.primaryGoldLight,
                    border: MyShopColors.primaryGold,
                    onTap: () {},
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DirectHelpCard(
                    iconBg: MyShopColors.darkSlate,
                    icon: Icons.priority_high,
                    iconColor: MyShopColors.textOnDarkSlate,
                    title: 'Report an Issue',
                    subtitle: "Let us know if something isn't working",
                    background: MyShopColors.surfaceWhite,
                    border: MyShopColors.divider,
                    onTap: () {},
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'BROWSE TOPICS',
                          style: MyShopTypography.overline.copyWith(
                            color: MyShopColors.textSecondary,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {},
                        child: Text(
                          'View All',
                          style: MyShopTypography.body1.copyWith(
                            color: MyShopColors.primaryGold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: _TopicTile(
                          icon: Icons.person_outline,
                          label: 'Account Access',
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.md),
                      Expanded(
                        child: _TopicTile(
                          icon: Icons.credit_card,
                          label: 'Payments & Billing',
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _TopicTile(
                          icon: Icons.shield_outlined,
                          label: 'Privacy & Safety',
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.md),
                      Expanded(
                        child: _TopicTile(
                          icon: Icons.gpp_maybe_outlined,
                          label: 'Fraud Prevention',
                          onTap: () {},
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _LegalCard(),
                  const SizedBox(height: MyShopSpacing.xl),
                  const _AppInfoFooter(),
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
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
            'Support & Legal',
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
// Search bar + commonly searched
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search,
            size: 20,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: TextField(
              style: MyShopTypography.body1,
              decoration: InputDecoration(
                hintText: 'Search help articles...',
                hintStyle: MyShopTypography.body1.copyWith(
                  color: MyShopColors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommonlySearched extends StatelessWidget {
  const _CommonlySearched();

  @override
  Widget build(BuildContext context) {
    final linkStyle = MyShopTypography.body2.copyWith(
      color: MyShopColors.primaryGold,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: MyShopColors.primaryGold,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.sm),
      child: RichText(
        text: TextSpan(
          style: MyShopTypography.body2,
          children: [
            const TextSpan(text: 'Commonly searched: '),
            TextSpan(text: 'Refund policy', style: linkStyle),
            const TextSpan(text: ', '),
            TextSpan(text: 'Account safety', style: linkStyle),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Direct help card
// ─────────────────────────────────────────────────────────────────────────────

class _DirectHelpCard extends StatelessWidget {
  const _DirectHelpCard({
    required this.iconBg,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.border,
    required this.onTap,
  });

  final Color iconBg;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color background;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: MyShopTypography.h3.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: MyShopTypography.body2),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: MyShopColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Topic tile
// ─────────────────────────────────────────────────────────────────────────────

class _TopicTile extends StatelessWidget {
  const _TopicTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: MyShopColors.textPrimary),
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              label,
              style: MyShopTypography.h3.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legal card
// ─────────────────────────────────────────────────────────────────────────────

class _LegalCard extends StatelessWidget {
  const _LegalCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.sm),
            child: Row(
              children: [
                const Icon(
                  Icons.balance,
                  size: 18,
                  color: MyShopColors.textSecondary,
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Text(
                  'LEGAL & POLICIES',
                  style: MyShopTypography.overline.copyWith(
                    color: MyShopColors.textSecondary,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const _LegalRow(label: 'Terms of Service'),
          const _LegalDivider(),
          const _LegalRow(label: 'Privacy Policy'),
          const _LegalDivider(),
          const _LegalRow(label: 'Acceptable Use Policy'),
          const _LegalDivider(),
          const _LegalRow(label: 'Community Guidelines'),
          const _LegalDivider(),
          const _LegalRow(label: 'Third-Party Licenses', isExternal: true),
          const _LegalDivider(),
          const _LegalRow(label: 'Cookie Settings'),
        ],
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow({required this.label, this.isExternal = false});

  final String label;
  final bool isExternal;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: MyShopTypography.h3.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              isExternal ? Icons.open_in_new : Icons.chevron_right,
              size: isExternal ? 18 : 22,
              color: MyShopColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalDivider extends StatelessWidget {
  const _LegalDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, color: MyShopColors.divider);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// App info footer
// ─────────────────────────────────────────────────────────────────────────────

class _AppInfoFooter extends StatelessWidget {
  const _AppInfoFooter();

  @override
  Widget build(BuildContext context) {
    final linkStyle = MyShopTypography.body2.copyWith(
      color: MyShopColors.primaryGold,
      fontWeight: FontWeight.w800,
      decoration: TextDecoration.underline,
      decorationColor: MyShopColors.primaryGold,
    );
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: MyShopColors.primaryGold,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                size: 20,
                color: MyShopColors.textOnPrimary,
              ),
            ),
            const SizedBox(width: MyShopSpacing.sm),
            Text(
              'MyShop Provider App',
              style: MyShopTypography.h3.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.sm),
        Text(
          'Version 2.4.1 (Build 8820)',
          style: MyShopTypography.body2,
        ),
        const SizedBox(height: 2),
        Text(
          '© 2026 Gilmore Tech. All Rights Reserved.',
          style: MyShopTypography.body2,
        ),
        const SizedBox(height: 4),
        RichText(
          text: TextSpan(
            style: MyShopTypography.body2,
            children: [
              TextSpan(text: 'Data Policy', style: linkStyle),
              const TextSpan(text: '  ·  '),
              TextSpan(text: 'Compliance', style: linkStyle),
            ],
          ),
        ),
      ],
    );
  }
}
