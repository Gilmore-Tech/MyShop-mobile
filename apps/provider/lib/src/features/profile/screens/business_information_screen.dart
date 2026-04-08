import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// Business Information screen — artisan-only.
///
/// PRD Reference: PRD 5.3 — verified artisan profile.
class BusinessInformationScreen extends StatelessWidget {
  const BusinessInformationScreen({
    super.key,
    this.businessName = 'Bright Spark Electrical',
    this.tier = 'Master Artisan',
    this.cityRegion = 'Accra, Ghana',
    this.rating = 4.9,
    this.jobsCount = 128,
    this.legalType = 'Sole Trader',
    this.founded = 'May 2018',
    this.taxId = 'GHA-102933',
    this.employees = '12 Members',
    this.serviceRadius = '15km Radius',
    this.serviceArea = 'Osu',
    this.regulationDaysUntilInspection = 14,
  });

  final String businessName;
  final String tier;
  final String cityRegion;
  final double rating;
  final int jobsCount;
  final String legalType;
  final String founded;
  final String taxId;
  final String employees;
  final String serviceRadius;
  final String serviceArea;
  final int regulationDaysUntilInspection;

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
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: MyShopSpacing.md,
                ),
                children: [
                  _HeroCard(
                    businessName: businessName,
                    tier: tier,
                    cityRegion: cityRegion,
                    rating: rating,
                    jobsCount: jobsCount,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      const Icon(
                        Icons.work_outline,
                        size: 18,
                        color: MyShopColors.primaryGold,
                      ),
                      const SizedBox(width: MyShopSpacing.sm),
                      Text(
                        'ENTERPRISE PROFILE',
                        style: MyShopTypography.overline.copyWith(
                          color: MyShopColors.textSecondary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.work_outline,
                          label: 'LEGAL TYPE',
                          value: legalType,
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.md),
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.calendar_today_outlined,
                          label: 'FOUNDED',
                          value: founded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.description_outlined,
                          label: 'TAX ID',
                          value: taxId,
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.md),
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.group_outlined,
                          label: 'EMPLOYEES',
                          value: employees,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  _ComplianceCard(
                    docs: const [
                      _ComplianceDoc(
                        title: 'Trade License (Artisan)',
                        expires: 'Expires: Oct 12, 2025',
                      ),
                      _ComplianceDoc(
                        title: 'Business Registration',
                        expires: 'Expires: Mar 04, 2024',
                      ),
                      _ComplianceDoc(
                        title: 'Tax Clearance (TIN)',
                        expires: 'Expires: Dec 31, 2024',
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  _RegulationNotice(
                    daysUntilInspection: regulationDaysUntilInspection,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      const Icon(
                        Icons.near_me_outlined,
                        size: 16,
                        color: MyShopColors.textSecondary,
                      ),
                      const SizedBox(width: MyShopSpacing.sm),
                      Text(
                        'SERVICE COVERAGE',
                        style: MyShopTypography.overline.copyWith(
                          color: MyShopColors.textSecondary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _ServiceCoverageCard(
                    radiusLabel: '$serviceRadius · $serviceArea',
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
            _Footer(),
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
          Expanded(
            child: Text(
              'Business Info',
              style: MyShopTypography.h1.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.md,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: MyShopColors.divider),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: MyShopColors.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Edit',
                    style: MyShopTypography.body1.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.businessName,
    required this.tier,
    required this.cityRegion,
    required this.rating,
    required this.jobsCount,
  });

  final String businessName;
  final String tier;
  final String cityRegion;
  final double rating;
  final int jobsCount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 220,
        decoration: const BoxDecoration(color: MyShopColors.darkSlate),
        child: Stack(
          children: [
            // Placeholder hero image — gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      MyShopColors.darkSlate,
                      MyShopColors.darkText,
                    ],
                  ),
                ),
              ),
            ),
            // Bottom dark gradient for text legibility
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
            ),

            // Verified pill
            Positioned(
              top: MyShopSpacing.md,
              right: MyShopSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.success,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: MyShopColors.textOnPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'VERIFIED',
                      style: MyShopTypography.caption.copyWith(
                        color: MyShopColors.textOnPrimary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Rating chip
            Positioned(
              bottom: MyShopSpacing.md,
              right: MyShopSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: MyShopSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.star_border,
                          size: 16,
                          color: MyShopColors.primaryGold,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          rating.toStringAsFixed(1),
                          style: MyShopTypography.h3.copyWith(
                            color: MyShopColors.textOnDarkSlate,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$jobsCount JOBS',
                      style: MyShopTypography.caption.copyWith(
                        color: MyShopColors.textOnDarkSlate
                            .withValues(alpha: 0.85),
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom-left text stack
            Positioned(
              left: MyShopSpacing.md,
              right: 110,
              bottom: MyShopSpacing.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    businessName,
                    style: MyShopTypography.h1.copyWith(
                      color: MyShopColors.textOnDarkSlate,
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tier,
                          style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.textOnDarkSlate,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.sm),
                      const Icon(
                        Icons.location_on,
                        size: 14,
                        color: MyShopColors.primaryGold,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          cityRegion,
                          style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.primaryGold,
                            fontWeight: FontWeight.w800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
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
// Info tile (2-column grid)
// ─────────────────────────────────────────────────────────────────────────────

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
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
            child: Icon(icon, size: 18, color: MyShopColors.textPrimary),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MyShopTypography.overline.copyWith(
                    color: MyShopColors.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
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
// Compliance card
// ─────────────────────────────────────────────────────────────────────────────

class _ComplianceDoc {
  const _ComplianceDoc({required this.title, required this.expires});

  final String title;
  final String expires;
}

class _ComplianceCard extends StatelessWidget {
  const _ComplianceCard({required this.docs});

  final List<_ComplianceDoc> docs;

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
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 18,
                color: MyShopColors.textPrimary,
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Text(
                  'Compliance & Docs',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceGrey,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${docs.length} Valid',
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          for (int i = 0; i < docs.length; i++) ...[
            _ComplianceRow(doc: docs[i]),
            if (i < docs.length - 1) const SizedBox(height: MyShopSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _ComplianceRow extends StatelessWidget {
  const _ComplianceRow({required this.doc});

  final _ComplianceDoc doc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: MyShopColors.textPrimary,
                width: 1.4,
              ),
            ),
            child: const Icon(
              Icons.check,
              size: 18,
              color: MyShopColors.textPrimary,
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.access_time,
                      size: 12,
                      color: MyShopColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Text(doc.expires, style: MyShopTypography.body2),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.successLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Valid',
                  style: MyShopTypography.body2.copyWith(
                    color: MyShopColors.success,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () {},
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View',
                      style: MyShopTypography.body1.copyWith(
                        color: MyShopColors.primaryGold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: MyShopColors.primaryGold,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Regulation notice
// ─────────────────────────────────────────────────────────────────────────────

class _RegulationNotice extends StatelessWidget {
  const _RegulationNotice({required this.daysUntilInspection});

  final int daysUntilInspection;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceWhite,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.info_outline,
              size: 18,
              color: MyShopColors.primaryGold,
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Regulation Notice',
                  style: MyShopTypography.h3.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'In accordance with Ghana GPRTU & Local Assembly guidelines, all certified artisans must renew trade licenses annually. Your next inspection is due in $daysUntilInspection days.',
                  style: MyShopTypography.body2.copyWith(height: 1.5),
                ),
                const SizedBox(height: MyShopSpacing.sm),
                GestureDetector(
                  onTap: () {},
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Schedule Inspection',
                        style: MyShopTypography.body1.copyWith(
                          color: MyShopColors.primaryGold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: MyShopColors.primaryGold,
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
// Service coverage card
// ─────────────────────────────────────────────────────────────────────────────

class _ServiceCoverageCard extends StatelessWidget {
  const _ServiceCoverageCard({required this.radiusLabel});

  final String radiusLabel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          // Map placeholder
          Container(
            height: 160,
            color: const Color(0xFFE6EAEC),
            alignment: Alignment.center,
            child: const Icon(
              Icons.location_on,
              size: 56,
              color: MyShopColors.error,
            ),
          ),
          // Radius pill
          Positioned(
            left: 0,
            right: 0,
            bottom: MyShopSpacing.md + 8,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  radiusLabel,
                  style: MyShopTypography.body1.copyWith(
                    color: MyShopColors.textOnDarkSlate,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          // Manage Area button
          Positioned(
            right: MyShopSpacing.md,
            bottom: MyShopSpacing.sm,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.md,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Manage Area',
                  style: MyShopTypography.body1.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
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
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MyShopColors.divider),
                ),
                alignment: Alignment.center,
                child: Text(
                  'View History',
                  style: MyShopTypography.button.copyWith(
                    color: MyShopColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            flex: 6,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Request Validation',
                  style: MyShopTypography.button.copyWith(
                    color: MyShopColors.textOnDarkSlate,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
