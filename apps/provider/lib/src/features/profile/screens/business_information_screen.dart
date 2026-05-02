import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/current_user_provider.dart';
import '../providers/verification_provider.dart';

/// Business Information screen — artisan-only.
///
/// PRD Reference: PRD 5.3 — verified artisan profile.
/// Reads real data from currentUserProvider (AuthUser + ArtisanProfile).
class BusinessInformationScreen extends ConsumerWidget {
  const BusinessInformationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final ap = user?.artisanProfile;
    final completion = ref.watch(profileCompletionProvider);

    final businessName =
        ap?.businessName ?? user?.displayName ?? 'Your Business';
    final categories =
        ap?.serviceCategories?.map((sc) => sc.category.name).join(', ') ??
            'No categories';
    final serviceRadius = '${ap?.serviceRadiusKm.toStringAsFixed(0) ?? '5'}km';
    final shopCapacity = ap?.shopCapacity ?? 'solo';
    final maxJobs = ap?.maxConcurrentJobs ?? 1;
    final jobsDone = ap?.completedJobsCount ?? 0;
    final verificationStatus = ap?.verificationStatus ?? 'pending';
    final isVerified = verificationStatus == 'approved';

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
                    categories: categories,
                    isVerified: isVerified,
                    jobsCount: jobsDone,
                  ),
                  const SizedBox(height: MyShopSpacing.lg),

                  // Enterprise profile section
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
                          icon: Icons.category_outlined,
                          label: 'SERVICES',
                          value: categories,
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.md),
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.group_outlined,
                          label: 'CAPACITY',
                          value:
                              '${shopCapacity[0].toUpperCase()}${shopCapacity.substring(1)} · $maxJobs job${maxJobs > 1 ? 's' : ''}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.verified_outlined,
                          label: 'VERIFICATION',
                          value: verificationStatus[0].toUpperCase() +
                              verificationStatus.substring(1),
                        ),
                      ),
                      const SizedBox(width: MyShopSpacing.md),
                      Expanded(
                        child: _InfoTile(
                          icon: Icons.build_outlined,
                          label: 'JOBS COMPLETED',
                          value: jobsDone.toString(),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: MyShopSpacing.lg),

                  // Profile completion
                  if (!completion.isComplete) ...[
                    _CompletionCard(completion: completion),
                    const SizedBox(height: MyShopSpacing.md),
                  ],

                  // Service coverage
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
                    radiusLabel: '$serviceRadius Radius',
                    latitude: ap?.serviceLatitude,
                    longitude: ap?.serviceLongitude,
                    radiusKm: ap?.serviceRadiusKm ?? 5,
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

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

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
            onTap: () => context.push('/account/business/edit'),
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

// ---------------------------------------------------------------------------
// Hero card
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.businessName,
    required this.categories,
    required this.isVerified,
    required this.jobsCount,
  });

  final String businessName;
  final String categories;
  final bool isVerified;
  final int jobsCount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 200,
        decoration: const BoxDecoration(color: MyShopColors.darkSlate),
        child: Stack(
          children: [
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

            // Verified / Pending pill
            Positioned(
              top: MyShopSpacing.md,
              right: MyShopSpacing.md,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      isVerified ? MyShopColors.success : MyShopColors.warning,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVerified
                          ? Icons.shield_outlined
                          : Icons.hourglass_empty,
                      size: 14,
                      color: MyShopColors.textOnPrimary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isVerified ? 'VERIFIED' : 'PENDING',
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

            // Stats chip
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
                child: Text(
                  '$jobsCount JOBS',
                  style: MyShopTypography.caption.copyWith(
                    color: MyShopColors.textOnDarkSlate,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),

            // Bottom-left text
            Positioned(
              left: MyShopSpacing.md,
              right: 80,
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Text(
                    categories,
                    style: MyShopTypography.body2.copyWith(
                      color: MyShopColors.primaryGold,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ---------------------------------------------------------------------------
// Info tile
// ---------------------------------------------------------------------------

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
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile completion card
// ---------------------------------------------------------------------------

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.completion});

  final ProfileCompletion completion;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.primaryGoldLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.info_outline,
                size: 18,
                color: MyShopColors.primaryGold,
              ),
              const SizedBox(width: MyShopSpacing.sm),
              Text(
                'Profile ${completion.percentage}% complete',
                style: MyShopTypography.h3.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: MyShopSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: completion.progress,
              minHeight: 6,
              backgroundColor: MyShopColors.surfaceGrey,
              valueColor: const AlwaysStoppedAnimation<Color>(
                MyShopColors.primaryGold,
              ),
            ),
          ),
          if (completion.missing.isNotEmpty) ...[
            const SizedBox(height: MyShopSpacing.sm),
            Text(
              'Missing: ${completion.missing.join(', ')}',
              style: MyShopTypography.body2,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Service coverage card
// ---------------------------------------------------------------------------

class _ServiceCoverageCard extends StatelessWidget {
  const _ServiceCoverageCard({
    required this.radiusLabel,
    required this.radiusKm,
    this.latitude,
    this.longitude,
  });

  final String radiusLabel;
  final double? latitude;
  final double? longitude;
  final double radiusKm;

  bool get _hasLocation => latitude != null && longitude != null;

  double _zoomForRadius(double km) {
    if (km <= 1) return 14;
    if (km <= 3) return 13;
    if (km <= 5) return 12.2;
    if (km <= 10) return 11.4;
    if (km <= 15) return 11;
    if (km <= 20) return 10.6;
    return 10.2;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          if (_hasLocation)
            SizedBox(
              height: 160,
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(latitude!, longitude!),
                  zoom: _zoomForRadius(radiusKm),
                ),
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: false,
                liteModeEnabled: true,
                markers: {
                  Marker(
                    markerId: const MarkerId('service-centre'),
                    position: LatLng(latitude!, longitude!),
                  ),
                },
                circles: {
                  Circle(
                    circleId: const CircleId('service-area'),
                    center: LatLng(latitude!, longitude!),
                    radius: radiusKm * 1000,
                    fillColor: MyShopColors.primaryGold.withValues(alpha: 0.18),
                    strokeColor: MyShopColors.primaryGold,
                    strokeWidth: 2,
                  ),
                },
              ),
            )
          else
            Container(
              height: 160,
              color: const Color(0xFFE6EAEC),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.location_off_outlined,
                    size: 40,
                    color: MyShopColors.textSecondary,
                  ),
                  const SizedBox(height: MyShopSpacing.sm),
                  Text(
                    'No service area set',
                    style: MyShopTypography.body2.copyWith(
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
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
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

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
              onTap: () => context.push('/account/documents'),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: MyShopColors.darkSlate,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(
                  'Manage Documents',
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
