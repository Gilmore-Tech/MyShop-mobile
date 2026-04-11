import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/provider_type_provider.dart';

/// Documents & Verification — adapts to the active provider role.
///
/// - **Driver** sees a fixed set of required documents: Driver's License,
///   Roadworthiness, Insurance, Ghana Card.
/// - **Artisan** sees their core required docs (Ghana Card, Business
///   Certificate, Trade Certificate) plus an "Optional Documents" group for
///   SMEs that may not yet have full registration.
///
/// PRD Reference: PRD 5.5 — provider verification & compliance.
class DocumentsVerificationScreen extends ConsumerWidget {
  const DocumentsVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isArtisan = ref.watch(providerTypeProvider).isArtisan;

    final requiredDocs = isArtisan ? _artisanRequired : _driverRequired;
    final optionalDocs = isArtisan ? _artisanOptional : const <_DocItem>[];

    final uploadedRequired =
        requiredDocs.where((d) => d.status != _DocStatus.missing).length;

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
                  _ProgressCard(
                    completed: uploadedRequired,
                    total: requiredDocs.length,
                    isArtisan: isArtisan,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: _SectionLabel(
                          icon: Icons.task_alt,
                          label: 'REQUIRED DOCUMENTS',
                          iconColor: MyShopColors.error,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: MyShopColors.errorLight,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Mandatory',
                          style: MyShopTypography.body2.copyWith(
                            color: MyShopColors.error,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  _DocsCard(items: requiredDocs),
                  if (optionalDocs.isNotEmpty) ...[
                    const SizedBox(height: MyShopSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: _SectionLabel(
                            icon: Icons.add_circle_outline,
                            label: 'OPTIONAL DOCUMENTS',
                            iconColor: MyShopColors.textSecondary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: MyShopColors.surfaceGrey,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'For SMEs',
                            style: MyShopTypography.body2.copyWith(
                              color: MyShopColors.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add these to unlock larger contracts and stand out to enterprise clients.',
                      style: MyShopTypography.body2.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    _DocsCard(items: optionalDocs),
                  ],
                  const SizedBox(height: MyShopSpacing.lg),
                  const _PolicyNote(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Driver doc set ──
  static const _driverRequired = <_DocItem>[
    _DocItem(
      icon: Icons.badge_outlined,
      title: "Driver's License",
      meta: 'Expires: Dec 12, 2027',
      status: _DocStatus.valid,
    ),
    _DocItem(
      icon: Icons.directions_car_outlined,
      title: 'Roadworthiness Certificate',
      meta: 'Expires: Mar 04, 2026',
      status: _DocStatus.valid,
    ),
    _DocItem(
      icon: Icons.shield_outlined,
      title: 'Vehicle Insurance',
      meta: 'Expires: Aug 22, 2025',
      status: _DocStatus.expiring,
    ),
    _DocItem(
      icon: Icons.credit_card,
      title: 'Ghana Card',
      meta: 'Tap to upload front & back',
      status: _DocStatus.missing,
    ),
  ];

  // ── Artisan doc sets ──
  static const _artisanRequired = <_DocItem>[
    _DocItem(
      icon: Icons.credit_card,
      title: 'Ghana Card',
      meta: 'Verified',
      status: _DocStatus.valid,
    ),
    _DocItem(
      icon: Icons.business_outlined,
      title: 'Business Registration Certificate',
      meta: 'Expires: Mar 04, 2026',
      status: _DocStatus.valid,
    ),
    _DocItem(
      icon: Icons.workspace_premium_outlined,
      title: 'Trade Certificate',
      meta: 'Tap to upload',
      status: _DocStatus.missing,
    ),
  ];

  static const _artisanOptional = <_DocItem>[
    _DocItem(
      icon: Icons.description_outlined,
      title: 'Tax Clearance (TIN)',
      meta: 'Recommended for VAT-eligible jobs',
      status: _DocStatus.missing,
    ),
    _DocItem(
      icon: Icons.health_and_safety_outlined,
      title: 'Public Liability Insurance',
      meta: 'Optional · unlocks enterprise contracts',
      status: _DocStatus.missing,
    ),
    _DocItem(
      icon: Icons.school_outlined,
      title: 'Professional Body Membership',
      meta: 'e.g. GNAT, GIA, GIE',
      status: _DocStatus.missing,
    ),
  ];
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
            'Documents & Verification',
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
// Progress card
// ─────────────────────────────────────────────────────────────────────────────

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.completed,
    required this.total,
    required this.isArtisan,
  });

  final int completed;
  final int total;
  final bool isArtisan;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    final isComplete = completed == total;
    final accent =
        isComplete ? MyShopColors.success : MyShopColors.primaryGold;
    final accentLight =
        isComplete ? MyShopColors.successLight : MyShopColors.primaryGoldLight;

    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: accentLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 1.4),
                ),
                child: Icon(
                  isComplete ? Icons.check : Icons.schedule,
                  size: 20,
                  color: accent,
                ),
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isComplete
                          ? 'All required documents submitted'
                          : 'Complete your verification',
                      style: MyShopTypography.h3.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArtisan
                          ? 'Artisan profile · $completed of $total required docs'
                          : 'Driver profile · $completed of $total required docs',
                      style: MyShopTypography.body2,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: MyShopColors.surfaceWhite,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: iconColor),
        const SizedBox(width: MyShopSpacing.sm),
        Text(
          label,
          style: MyShopTypography.overline.copyWith(
            color: MyShopColors.textSecondary,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Doc item + status
// ─────────────────────────────────────────────────────────────────────────────

enum _DocStatus { valid, expiring, missing }

class _DocItem {
  const _DocItem({
    required this.icon,
    required this.title,
    required this.meta,
    required this.status,
  });

  final IconData icon;
  final String title;
  final String meta;
  final _DocStatus status;
}

class _DocsCard extends StatelessWidget {
  const _DocsCard({required this.items});

  final List<_DocItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _DocRow(item: items[i]),
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

class _DocRow extends StatelessWidget {
  const _DocRow({required this.item});

  final _DocItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(10),
              ),
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
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (item.status != _DocStatus.missing)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.access_time,
                            size: 12,
                            color: MyShopColors.textSecondary,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          item.meta,
                          style: MyShopTypography.body2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: MyShopSpacing.sm),
            _StatusPill(status: item.status),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final _DocStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;
    late final IconData icon;

    switch (status) {
      case _DocStatus.valid:
        bg = MyShopColors.successLight;
        fg = MyShopColors.success;
        label = 'Valid';
        icon = Icons.check_circle_outline;
        break;
      case _DocStatus.expiring:
        bg = MyShopColors.warningLight;
        fg = MyShopColors.warning;
        label = 'Expiring';
        icon = Icons.warning_amber_outlined;
        break;
      case _DocStatus.missing:
        bg = MyShopColors.surfaceWhite;
        fg = MyShopColors.primaryGold;
        label = 'Upload';
        icon = Icons.upload_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: status == _DocStatus.missing ? MyShopColors.primaryGold : bg,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: MyShopTypography.body2.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Policy note
// ─────────────────────────────────────────────────────────────────────────────

class _PolicyNote extends StatelessWidget {
  const _PolicyNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 18,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              'Documents are encrypted in transit and reviewed by our compliance team within 24 hours.',
              style: MyShopTypography.body2.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
