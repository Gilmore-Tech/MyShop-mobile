import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';

/// Single welcome screen — replaces the old 3-slide carousel.
///
/// Top half: a brand-aligned hero composition showing the two sides of the
/// MyShop provider platform (driver + artisan). Bottom half: headline, value
/// props, primary "Get Started" CTA, and a sign-in shortcut.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

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
              const _PlatformHero(),
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
                      onPressed: () => _markSeenAndGo(ref, context, '/signup/role'),
                    ),
                    const SizedBox(height: MyShopSpacing.sm),
                    TextButton(
                      onPressed: () => _markSeenAndGo(ref, context, '/signin/phone'),
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

/// Hero composition shown at the top of the welcome screen. Renders a soft
/// gold backdrop with two stacked "platform" cards — one for drivers and one
/// for artisans — communicating the dual-sided product without needing any
/// custom illustration assets.
class _PlatformHero extends StatelessWidget {
  const _PlatformHero();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.lg,
        topInset + MyShopSpacing.md,
        MyShopSpacing.lg,
        MyShopSpacing.xl,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            MyShopColors.primaryGoldLight,
            MyShopColors.surfaceWhite,
          ],
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(32),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Decorative gold halo behind the cards.
          Positioned(
            top: 24,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: MyShopColors.primaryGold.withValues(alpha: 0.18),
              ),
            ),
          ),
          // Decorative ring.
          Positioned(
            top: 8,
            right: 12,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: MyShopColors.primaryGold.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -8,
            left: 4,
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: MyShopColors.primaryGoldDark,
              ),
            ),
          ),
          SizedBox(
            height: 280,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Driver card — tilted slightly left, sits behind.
                Positioned(
                  left: 0,
                  top: 24,
                  child: Transform.rotate(
                    angle: -0.08,
                    child: const _PlatformCard(
                      icon: Icons.directions_car_filled_rounded,
                      label: 'DRIVERS',
                      title: 'Pick up rides',
                      subtitle: 'Live trips • Fare meter • Navigation',
                      accent: MyShopColors.darkSlate,
                    ),
                  ),
                ),
                // Artisan card — tilted slightly right, sits in front.
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Transform.rotate(
                    angle: 0.06,
                    child: const _PlatformCard(
                      icon: Icons.handyman_rounded,
                      label: 'ARTISANS',
                      title: 'Win new jobs',
                      subtitle: 'Bid • Chat • Get paid',
                      accent: MyShopColors.primaryGoldDark,
                    ),
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

/// One of the two phone-style cards shown inside the hero.
class _PlatformCard extends StatelessWidget {
  const _PlatformCard({
    required this.icon,
    required this.label,
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String title;
  final String subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: MyShopColors.darkText.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 24, color: accent),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            label,
            style: MyShopTypography.overline.copyWith(color: accent),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: MyShopTypography.h3,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: MyShopTypography.caption,
            maxLines: 2,
          ),
          const SizedBox(height: MyShopSpacing.sm),
          Container(
            height: 4,
            width: 60,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
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
