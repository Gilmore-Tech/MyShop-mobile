import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';

/// Single welcome screen — edge-to-edge hero photo on top, copy + CTAs below.
///
/// Matches the client app's onboarding pattern: the hero image bleeds under
/// the status bar with only its bottom corners rounded; headline, value
/// props, and CTAs render in a padded column underneath.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  static const _heroImage = 'assets/images/onboarding_provider.jpg';

  static const _highlights = <_Highlight>[
    _Highlight(
      icon: Icons.schedule_rounded,
      title: 'Earn on your own schedule',
      subtitle: 'Drive or offer artisan services across the Ashanti Region.',
    ),
    _Highlight(
      icon: Icons.payments_outlined,
      title: 'Instant MoMo payouts',
      subtitle: 'Get paid the moment a job or trip is complete.',
    ),
    _Highlight(
      icon: Icons.verified_user_outlined,
      title: 'Verified and protected',
      subtitle: 'Background checks, in-app safety tools, and 24/7 support.',
    ),
  ];

  void _markSeenAndGo(WidgetRef ref, BuildContext context, String route) {
    ref.read(tokenStorageProvider).markOnboardingSeen();
    ref.read(hasSeenOnboardingProvider.notifier).state = true;
    context.go(route);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            children: [
              const _Hero(heroImage: _heroImage),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.lg,
                  MyShopSpacing.xl,
                  MyShopSpacing.lg,
                  MyShopSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome to MyShop',
                      textAlign: TextAlign.center,
                      style: MyShopTypography.h1,
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    Text(
                      'One app for drivers and artisans across Ghana. '
                      'Pick up rides, take on jobs, and get paid instantly.',
                      textAlign: TextAlign.center,
                      style: MyShopTypography.body2,
                    ),
                    const SizedBox(height: MyShopSpacing.lg),
                    for (var i = 0; i < _highlights.length; i++) ...[
                      _HighlightRow(highlight: _highlights[i]),
                      if (i < _highlights.length - 1)
                        const SizedBox(height: MyShopSpacing.md),
                    ],
                    const SizedBox(height: MyShopSpacing.xl),
                    MyShopPrimaryButton(
                      label: 'Get Started',
                      icon: Icons.arrow_forward_rounded,
                      onPressed: () =>
                          _markSeenAndGo(ref, context, '/signup/role'),
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    TextButton(
                      onPressed: () =>
                          _markSeenAndGo(ref, context, '/signin/phone'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        foregroundColor: MyShopColors.primaryGoldDark,
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'Already have an account? ',
                              style: MyShopTypography.body1.copyWith(
                                color: MyShopColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            TextSpan(
                              text: 'Sign in',
                              style: MyShopTypography.body1.copyWith(
                                color: MyShopColors.primaryGoldDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Hero ─────────────────────────────────────────────────────────────────────

/// Full-bleed photo hero with a pill badge top-left. Bleeds under the status
/// bar; only bottom corners are rounded so the image flows from the top edge.
///
/// Renders a gradient fallback when [heroImage] isn't present in the bundle
/// yet — keeps the screen looking intentional during the gap between wiring
/// and asset drop.
class _Hero extends StatelessWidget {
  const _Hero({required this.heroImage});

  final String heroImage;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final heroHeight = size.height * 0.46;
    final topInset = MediaQuery.paddingOf(context).top;

    return SizedBox(
      width: double.infinity,
      height: heroHeight,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Gradient fallback — always painted underneath so a missing
            // / slow-decoding asset never leaves the area blank.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1F2A35),
                    MyShopColors.primaryGoldDark,
                  ],
                ),
              ),
            ),
            Image.asset(
              heroImage,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
            // Dark gradient overlay — keeps the pill badge legible over any
            // photo and softens the bottom edge into the page background.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.30),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.30),
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            Positioned(
              top: topInset + MyShopSpacing.md,
              left: MyShopSpacing.lg,
              child: const _PillBadge(
                icon: Icons.workspace_premium_rounded,
                label: 'EARN WITH MYSHOP',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.md,
        vertical: MyShopSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(MyShopRadius.pill),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MyShopColors.primaryGoldDark),
          const SizedBox(width: 6),
          Text(
            label,
            style: MyShopTypography.body1.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: MyShopColors.textPrimary,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _Highlight {
  const _Highlight({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({required this.highlight});

  final _Highlight highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: MyShopColors.primaryGoldLight,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: MyShopColors.primaryGoldDark,
            size: 22,
          ),
        ),
        const SizedBox(width: MyShopSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                highlight.title,
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(highlight.subtitle, style: MyShopTypography.body2),
            ],
          ),
        ),
        const SizedBox(width: MyShopSpacing.sm),
        Icon(
          highlight.icon,
          size: 22,
          color: MyShopColors.textSecondary,
        ),
      ],
    );
  }
}
