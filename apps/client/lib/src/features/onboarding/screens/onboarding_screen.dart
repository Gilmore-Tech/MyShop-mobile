import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart';
import '../../auth/providers/auth_controller.dart';
import '../../profile/providers/app_preferences_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _isFinishing = false;

  static const _pages = <_OnboardingPage>[
    _OnboardingPage(
      pillIcon: Icons.verified_user_rounded,
      pillLabel: 'Verified Network',
      heroIcon: Icons.shield_rounded,
      heroAccentLabel: 'TRUSTED ACROSS',
      heroAccentValue: 'Ashanti Region',
      title: 'Safety & Trust',
      description:
          'Verified providers, emergency button, masked calls, and live trip sharing with family — built in.',
      socialProof: '20k+ verified providers',
      footnote: 'Smile Identity KYC Verified',
      gradient: [Color(0xFF1F2A35), Color(0xFF46535D)],
    ),
    _OnboardingPage(
      pillIcon: Icons.location_on_rounded,
      pillLabel: 'Always Live',
      heroIcon: Icons.my_location_rounded,
      heroAccentLabel: 'LIVE TRACKING IN',
      heroAccentValue: 'Real Time',
      title: 'Track Everything Live',
      description:
          'Real-time GPS for rides, live status for artisan jobs, and shareable links with trusted contacts.',
      socialProof: '100% trips tracked',
      footnote: 'Powered by Mapbox & Google Maps',
      gradient: [Color(0xFF0E2A47), Color(0xFF2F80ED)],
    ),
    _OnboardingPage(
      pillIcon: Icons.bolt_rounded,
      pillLabel: 'Loyalty Rewards',
      heroIcon: Icons.workspace_premium_rounded,
      heroAccentLabel: 'EARN AS YOU',
      heroAccentValue: 'Ride & Hire',
      title: 'Earn While You Spend',
      description:
          'Loyalty points on every ride and job, referral bonuses, and redeem for instant discounts.',
      socialProof: '50k+ satisfied riders',
      footnote: 'Cedis-native rewards • No expiry',
      gradient: [Color(0xFF3F2A12), Color(0xFFD48E1A)],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _markSeenAndGo() async {
    if (_isFinishing || !mounted) return;
    setState(() => _isFinishing = true);

    // Sticky flag — user has now seen onboarding at least once.
    await ref.read(tokenStorageProvider).markOnboardingSeen();
    if (!mounted) return;
    ref.read(hasSeenOnboardingProvider.notifier).state = true;

    // One-shot replay flag — clear both the SharedPrefs key and the
    // top-level mirror the router watches, so the next launch lands on
    // home instead of bouncing back here.
    await ref
        .read(appPreferencesProvider.notifier)
        .toggleReplayOnboarding(false);
    if (!mounted) return;
    ref.read(pendingReplayOnboardingProvider.notifier).state = false;

    // Router redirect handles routing from here based on auth state
    // (unauth → phone screen, auth → home).
    context.go(AppRoutes.home);
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      _markSeenAndGo();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _pages.length - 1;

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              showSkip: !isLast,
              onSkip: _markSeenAndGo,
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _OnboardingPageView(page: _pages[i]),
              ),
            ),
            _PageDots(count: _pages.length, index: _index),
            const SizedBox(height: MyShopSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.lg,
              ),
              child: MyShopPrimaryButton(
                label: isLast ? 'Get Started' : 'Next',
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: _next,
              ),
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MyShopSpacing.lg,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.shield_outlined,
                    size: 14,
                    color: MyShopColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _pages[_index].footnote,
                    style: MyShopTypography.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: MyShopSpacing.md),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.showSkip, required this.onSkip});

  final bool showSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: MyShopSpacing.lg,
        vertical: MyShopSpacing.sm,
      ),
      child: SizedBox(
        height: 32,
        child: Align(
          alignment: Alignment.centerRight,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: showSkip ? 1 : 0,
            child: TextButton(
              onPressed: showSkip ? onSkip : null,
              style: TextButton.styleFrom(
                foregroundColor: MyShopColors.textPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: MyShopSpacing.sm,
                ),
                minimumSize: const Size(48, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Skip',
                style: MyShopTypography.body1.copyWith(
                  color: MyShopColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: MyShopSpacing.sm),
          Expanded(flex: 5, child: _HeroCard(page: page)),
          const SizedBox(height: MyShopSpacing.xl),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: MyShopTypography.display.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            page.description,
            textAlign: TextAlign.center,
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          const Spacer(),
          _SocialProofRow(label: page.socialProof),
          const SizedBox(height: MyShopSpacing.md),
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.page});

  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.clamp(0, 360).toDouble();
        return Center(
          child: AspectRatio(
            aspectRatio: 0.78,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: page.gradient,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: page.gradient.last.withValues(alpha: 0.25),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: -40,
                      right: -40,
                      child: _glowOrb(160, 0.18),
                    ),
                    Positioned(
                      bottom: -30,
                      left: -30,
                      child: _glowOrb(120, 0.12),
                    ),
                    Center(
                      child: Container(
                        width: 132,
                        height: 132,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Icon(
                          page.heroIcon,
                          size: 64,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                    Positioned(
                      top: MyShopSpacing.md,
                      left: MyShopSpacing.md,
                      child: _PillBadge(
                        icon: page.pillIcon,
                        label: page.pillLabel,
                      ),
                    ),
                    Positioned(
                      left: MyShopSpacing.md,
                      right: MyShopSpacing.md,
                      bottom: MyShopSpacing.md,
                      child: _ActiveStrip(
                        label: page.heroAccentLabel,
                        value: page.heroAccentValue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _glowOrb(double size, double alpha) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.white.withValues(alpha: alpha),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
      );
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
          Icon(icon, size: 14, color: MyShopColors.textPrimary),
          const SizedBox(width: 6),
          Text(
            label,
            style: MyShopTypography.body1.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: MyShopColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveStrip extends StatelessWidget {
  const _ActiveStrip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.sm + 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(MyShopRadius.card),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.navigation_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: MyShopSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: MyShopTypography.overline.copyWith(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: MyShopTypography.body1.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 1,
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

class _SocialProofRow extends StatelessWidget {
  const _SocialProofRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          height: 28,
          child: Stack(
            children: [
              for (var i = 0; i < 3; i++)
                Positioned(
                  left: i * 18.0,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _avatarColors[i],
                      border: Border.all(
                        color: MyShopColors.surfaceWhite,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.person_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: MyShopSpacing.sm),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: label.split(' ').first,
                style: MyShopTypography.body1.copyWith(
                  fontWeight: FontWeight.w800,
                  color: MyShopColors.textPrimary,
                ),
              ),
              TextSpan(
                text: ' ${label.split(' ').skip(1).join(' ')}',
                style: MyShopTypography.body1.copyWith(
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const _avatarColors = [
    Color(0xFFB57655),
    Color(0xFFCFCFCF),
    Color(0xFF9DB7C9),
  ];
}

class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final selected = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: selected ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: selected ? MyShopColors.darkText : MyShopColors.divider,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.pillIcon,
    required this.pillLabel,
    required this.heroIcon,
    required this.heroAccentLabel,
    required this.heroAccentValue,
    required this.title,
    required this.description,
    required this.socialProof,
    required this.footnote,
    required this.gradient,
  });

  final IconData pillIcon;
  final String pillLabel;
  final IconData heroIcon;
  final String heroAccentLabel;
  final String heroAccentValue;
  final String title;
  final String description;
  final String socialProof;
  final String footnote;
  final List<Color> gradient;
}
