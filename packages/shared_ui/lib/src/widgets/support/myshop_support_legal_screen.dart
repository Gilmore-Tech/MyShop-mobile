import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import 'support_legal_config.dart';

/// Lifted Support & Legal home — both apps render this same widget.
///
/// Differences across apps come in via [SupportLegalConfig]:
///   - audience-tagged help articles + legal docs
///   - app name / version / copyright shown in the footer
///   - support contact channels
///   - all navigation callbacks (each app's router stays the source of
///     truth on routes)
///
/// Help categories are passed in by the caller — letting the per-app
/// provider decide between "loading skeleton", "loaded", or "fall back to
/// hardcoded defaults if backend is down". Legal items are rendered from
/// [LegalSlugs.ordered]; titles fall back to [LegalSlugs.fallbackTitle]
/// when the document hasn't been hydrated yet.
class MyShopSupportLegalScreen extends StatelessWidget {
  const MyShopSupportLegalScreen({
    super.key,
    required this.config,
    required this.categoriesAsync,
    this.openTicketsBadge = 0,
  });

  final SupportLegalConfig config;

  /// Caller hands us the categories tri-state: data, loading, error. The
  /// shell renders skeletons while loading and a retry button on error.
  final SupportLegalAsync<List<HelpCategory>> categoriesAsync;

  /// Number of tickets that have unread agent replies. Drives the badge
  /// next to "My tickets".
  final int openTicketsBadge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
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
                  _SearchBar(onTap: () => config.onOpenSearch(null)),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionLabel(label: 'DIRECT HELP'),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DirectHelpCard(
                    iconBg: MyShopColors.primaryGold,
                    icon: Icons.chat_bubble_outline,
                    iconColor: MyShopColors.textOnPrimary,
                    title: 'Contact Support',
                    subtitle: 'WhatsApp, call, email, or open a ticket',
                    background: MyShopColors.primaryGoldLight,
                    border: MyShopColors.primaryGold,
                    onTap: config.onOpenContactSheet,
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DirectHelpCard(
                    iconBg: MyShopColors.darkSlate,
                    icon: Icons.flag_outlined,
                    iconColor: MyShopColors.textOnDarkSlate,
                    title: 'Report an Issue',
                    subtitle: "Let us know if something isn't working",
                    background: MyShopColors.surfaceWhite,
                    border: MyShopColors.divider,
                    onTap: () => config.onNewTicket(TicketCategory.bug),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _MyTicketsRow(
                    badge: openTicketsBadge,
                    onTap: config.onOpenTickets,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  _BrowseTopicsHeader(
                    onSearchTap: () => config.onOpenSearch(null),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _CategoriesGrid(
                    state: categoriesAsync,
                    onCategoryTap: config.onOpenCategory,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  _LegalCard(onOpen: config.onOpenLegal),
                  const SizedBox(height: MyShopSpacing.xl),
                  _AppInfoFooter(
                    appName: config.appName,
                    version: config.appVersion,
                    copyright: config.copyright,
                    onPrivacy: () => config.onOpenLegal(LegalSlugs.privacy),
                    onTerms: () => config.onOpenLegal(LegalSlugs.terms),
                  ),
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

/// Tri-state holder so the screen can render skeleton / loaded / error
/// without depending on Riverpod's `AsyncValue`. Per-app providers convert
/// from `AsyncValue<T>` into this when passing data down.
class SupportLegalAsync<T> {
  const SupportLegalAsync._(this.data, this.error, this.loading);

  const SupportLegalAsync.data(T value) : this._(value, null, false);

  const SupportLegalAsync.loading() : this._(null, null, true);

  const SupportLegalAsync.error(Object e) : this._(null, e, false);

  final T? data;
  final Object? error;
  final bool loading;

  bool get hasData => data != null;
  bool get hasError => error != null;
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
            onPressed: () => Navigator.of(context).maybePop(),
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
// Search bar (acts as a button — tap routes to search screen)
// ─────────────────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
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
              child: Text(
                'Search help articles…',
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
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
              child: Icon(icon, size: 18, color: iconColor),
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
// "My tickets" row with unread badge
// ─────────────────────────────────────────────────────────────────────────────

class _MyTicketsRow extends StatelessWidget {
  const _MyTicketsRow({required this.badge, required this.onTap});
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: MyShopColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: MyShopColors.surfaceGrey,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inbox_outlined,
                size: 20,
                color: MyShopColors.textPrimary,
              ),
            ),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'My tickets',
                    style: MyShopTypography.h3.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Track replies on tickets you have opened.',
                    style: MyShopTypography.body2,
                  ),
                ],
              ),
            ),
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  badge > 99 ? '99+' : '$badge',
                  style: MyShopTypography.caption.copyWith(
                    color: MyShopColors.textOnPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              )
            else
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
// "Browse Topics" header
// ─────────────────────────────────────────────────────────────────────────────

class _BrowseTopicsHeader extends StatelessWidget {
  const _BrowseTopicsHeader({required this.onSearchTap});
  final VoidCallback onSearchTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: _SectionLabel(label: 'BROWSE TOPICS')),
        GestureDetector(
          onTap: onSearchTap,
          child: Text(
            'Search',
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.primaryGold,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Categories grid (2 cols)
// ─────────────────────────────────────────────────────────────────────────────

class _CategoriesGrid extends StatelessWidget {
  const _CategoriesGrid({required this.state, required this.onCategoryTap});

  final SupportLegalAsync<List<HelpCategory>> state;
  final void Function(String slug) onCategoryTap;

  @override
  Widget build(BuildContext context) {
    if (state.loading) {
      return const _CategoriesSkeleton();
    }
    if (state.hasError && !state.hasData) {
      return _CategoriesError(error: state.error!);
    }
    final categories = state.data ?? const [];
    if (categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: MyShopSpacing.md),
        child: Text(
          'No help articles available yet — try contacting support.',
          style: MyShopTypography.body2,
        ),
      );
    }

    final tiles = categories
        .map(
          (c) => _CategoryTile(
            category: c,
            onTap: () => onCategoryTap(c.slug),
          ),
        )
        .toList();

    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(
        Row(
          children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: MyShopSpacing.md),
            if (i + 1 < tiles.length)
              Expanded(child: tiles[i + 1])
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      );
      if (i + 2 < tiles.length) {
        rows.add(const SizedBox(height: MyShopSpacing.md));
      }
    }
    return Column(children: rows);
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final HelpCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
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
              child: Icon(
                _iconFor(category.iconName),
                size: 18,
                color: MyShopColors.textPrimary,
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
            Text(
              category.title,
              style: MyShopTypography.h3.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (category.description != null) ...[
              const SizedBox(height: 2),
              Text(
                category.description!,
                style: MyShopTypography.body2,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Map backend icon hints (snake_case-ish names) to Material icons.
  /// Unrecognised hints fall back to the generic help icon — the backend
  /// can introduce new categories without a mobile release blocking on
  /// us shipping the icon mapping.
  static IconData _iconFor(String? hint) {
    switch (hint) {
      case 'account':
      case 'account_circle':
        return Icons.person_outline;
      case 'payments':
      case 'credit_card':
        return Icons.credit_card;
      case 'safety':
      case 'shield':
        return Icons.shield_outlined;
      case 'fraud':
        return Icons.gpp_maybe_outlined;
      case 'rides':
      case 'ride':
        return Icons.directions_car_outlined;
      case 'jobs':
      case 'job':
        return Icons.handyman_outlined;
      case 'payouts':
        return Icons.account_balance_wallet_outlined;
      case 'verification':
        return Icons.verified_user_outlined;
      case 'bug':
        return Icons.bug_report_outlined;
      default:
        return Icons.help_outline;
    }
  }
}

class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    Container tile() => Container(
          height: 96,
          decoration: BoxDecoration(
            color: MyShopColors.surfaceGrey,
            borderRadius: BorderRadius.circular(12),
          ),
        );
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: tile()),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(child: tile()),
          ],
        ),
        const SizedBox(height: MyShopSpacing.md),
        Row(
          children: [
            Expanded(child: tile()),
            const SizedBox(width: MyShopSpacing.md),
            Expanded(child: tile()),
          ],
        ),
      ],
    );
  }
}

class _CategoriesError extends StatelessWidget {
  const _CategoriesError({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            color: MyShopColors.error,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              "Couldn't load help topics. Pull to retry.",
              style: MyShopTypography.body2.copyWith(
                color: MyShopColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Legal card
// ─────────────────────────────────────────────────────────────────────────────

class _LegalCard extends StatelessWidget {
  const _LegalCard({required this.onOpen});
  final void Function(String slug) onOpen;

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
        border: Border.all(color: MyShopColors.divider),
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
          for (var i = 0; i < LegalSlugs.ordered.length; i++) ...[
            _LegalRow(
              slug: LegalSlugs.ordered[i],
              isExternal:
                  LegalSlugs.ordered[i] == LegalSlugs.thirdPartyLicenses,
              onTap: () => onOpen(LegalSlugs.ordered[i]),
            ),
            if (i < LegalSlugs.ordered.length - 1)
              const Divider(height: 1, color: MyShopColors.divider),
          ],
        ],
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.slug,
    required this.isExternal,
    required this.onTap,
  });

  final String slug;
  final bool isExternal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                LegalSlugs.fallbackTitle(slug),
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

// ─────────────────────────────────────────────────────────────────────────────
// App info footer
// ─────────────────────────────────────────────────────────────────────────────

class _AppInfoFooter extends StatelessWidget {
  const _AppInfoFooter({
    required this.appName,
    required this.version,
    required this.copyright,
    required this.onPrivacy,
    required this.onTerms,
  });

  final String appName;
  final String version;
  final String copyright;
  final VoidCallback onPrivacy;
  final VoidCallback onTerms;

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
              appName,
              style: MyShopTypography.h3.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
          ],
        ),
        const SizedBox(height: MyShopSpacing.sm),
        Text(version, style: MyShopTypography.body2),
        const SizedBox(height: 2),
        Text(copyright, style: MyShopTypography.body2),
        const SizedBox(height: 4),
        Wrap(
          children: [
            GestureDetector(
              onTap: onPrivacy,
              child: Text('Privacy', style: linkStyle),
            ),
            const Text('  ·  ', style: MyShopTypography.body2),
            GestureDetector(
              onTap: onTerms,
              child: Text('Terms', style: linkStyle),
            ),
          ],
        ),
      ],
    );
  }
}
