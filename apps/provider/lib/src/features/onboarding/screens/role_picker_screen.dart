import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../profile/providers/provider_type_provider.dart';
import '../../registration/providers/registration_controller.dart';

/// Role selection screen — two horizontal cards (Driver / Artisan) with a
/// reactive theme. Selecting a role morphs the background, accents, headline
/// and reveals a description + Continue CTA via smooth animations.
class RolePickerScreen extends ConsumerStatefulWidget {
  const RolePickerScreen({super.key, this.isSignIn = false});

  /// When true, selecting a role navigates to the sign-in phone screen
  /// instead of the sign-up registration flow.
  final bool isSignIn;

  @override
  ConsumerState<RolePickerScreen> createState() => _RolePickerScreenState();
}

class _RolePickerScreenState extends ConsumerState<RolePickerScreen> {
  ProviderType? _selected;

  static const _animDuration = Duration(milliseconds: 380);
  static const _animCurve = Curves.easeOutCubic;

  void _select(ProviderType role) {
    if (_selected == role) return;
    setState(() => _selected = role);
  }

  void _continue() {
    final role = _selected;
    if (role == null) return;
    ref.read(pendingRoleProvider.notifier).state = role;
    ref.read(providerTypeProvider.notifier).state = role;
    if (widget.isSignIn) {
      context.go('/signin/phone');
    } else {
      // This is a new role-registration review. Legal acknowledgement is
      // intentionally not shared across roles or carried from an abandoned
      // attempt, even when both roles use the same device.
      ref.read(termsAcceptedProvider(role).notifier).state = false;
      ref.read(privacyAcceptedProvider(role).notifier).state = false;
      ref.read(showRegistrationErrorsProvider.notifier).state = false;
      context.go(role.isDriver ? '/signup/driver' : '/signup/artisan');
    }
  }

  Color get _accent => switch (_selected) {
        ProviderType.driver => MyShopColors.darkSlate,
        ProviderType.artisan => MyShopColors.primaryGoldDark,
        null => MyShopColors.primaryGold,
      };

  static const _driverAsset = 'assets/images/role_driver.png';
  static const _artisanAsset = 'assets/images/role_artisan.png';

  String? get _bgAssetPath => switch (_selected) {
        ProviderType.driver => _driverAsset,
        ProviderType.artisan => _artisanAsset,
        null => null,
      };

  String get _headline => switch (_selected) {
        ProviderType.driver => widget.isSignIn
            ? 'Sign in as a driver'
            : "You're driving with MyShop",
        ProviderType.artisan => widget.isSignIn
            ? 'Sign in as an artisan'
            : "You're offering artisan services",
        null => widget.isSignIn ? 'Welcome back' : 'How will you earn?',
      };

  String get _subhead => switch (_selected) {
        ProviderType.driver => widget.isSignIn
            ? "We'll send a code to your registered phone number."
            : 'Quick rides, live navigation, and earnings recorded when a trip ends.',
        ProviderType.artisan => widget.isSignIn
            ? "We'll send a code to your registered phone number."
            : 'Win jobs in your trade, bid on requests, and track completed-work earnings.',
        null => widget.isSignIn
            ? 'Select your account type to continue.'
            : 'Choose the separate role account you want to create. One phone number may have one driver and one artisan account.',
      };

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected != null;
    final bgPath = _bgAssetPath;
    final headlineColor =
        hasSelection ? Colors.white : MyShopColors.textPrimary;
    final subheadColor = hasSelection
        ? Colors.white.withValues(alpha: 0.85)
        : MyShopColors.textSecondary;

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 0 — soft gradient (always present, visible when no role
          // is selected and behind the photo while it crossfades in).
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [MyShopColors.offWhite, MyShopColors.surfaceWhite],
                stops: [0, 0.55],
              ),
            ),
          ),
          // Layer 1 — selected role's hero image with a top-darken /
          // bottom-fade-to-white overlay for legibility.
          AnimatedSwitcher(
            duration: _animDuration,
            switchInCurve: _animCurve,
            switchOutCurve: _animCurve,
            child: bgPath == null
                ? const SizedBox.shrink(key: ValueKey('bg-none'))
                : Stack(
                    key: ValueKey('bg-${_selected!.name}'),
                    fit: StackFit.expand,
                    children: [
                      Image.asset(bgPath, fit: BoxFit.cover),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0x8C000000),
                              Color(0x00000000),
                              Color(0xFFFFFFFF),
                            ],
                            stops: [0, 0.40, 0.90],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          // Layer 2 — content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                MyShopSpacing.lg,
                MyShopSpacing.lg,
                MyShopSpacing.lg,
                MyShopSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: MyShopSpacing.md),
                  AnimatedSwitcher(
                    duration: _animDuration,
                    switchInCurve: _animCurve,
                    switchOutCurve: _animCurve,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.15),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Column(
                      key: ValueKey('headline-${_selected?.name ?? 'none'}'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedDefaultTextStyle(
                          duration: _animDuration,
                          curve: _animCurve,
                          style: MyShopTypography.h1.copyWith(
                            color: headlineColor,
                          ),
                          child: Text(_headline),
                        ),
                        const SizedBox(height: MyShopSpacing.sm),
                        AnimatedDefaultTextStyle(
                          duration: _animDuration,
                          curve: _animCurve,
                          style: MyShopTypography.body2.copyWith(
                            color: subheadColor,
                          ),
                          child: Text(_subhead),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.xl),
                  IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: _RoleCard(
                            role: ProviderType.driver,
                            selectedRole: _selected,
                            title: 'Driver',
                            tagline: 'Rides',
                            icon: Icons.directions_car_filled_rounded,
                            accent: MyShopColors.darkSlate,
                            assetPath: _driverAsset,
                            onTap: () => _select(ProviderType.driver),
                          ),
                        ),
                        const SizedBox(width: MyShopSpacing.md),
                        Expanded(
                          child: _RoleCard(
                            role: ProviderType.artisan,
                            selectedRole: _selected,
                            title: 'Artisan',
                            tagline: 'Skilled jobs',
                            icon: Icons.handyman_rounded,
                            accent: MyShopColors.primaryGoldDark,
                            assetPath: _artisanAsset,
                            onTap: () => _select(ProviderType.artisan),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.lg),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: _animDuration,
                      switchInCurve: _animCurve,
                      switchOutCurve: _animCurve,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.18),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: _selected == null
                          ? const _EmptyHint(key: ValueKey('empty'))
                          : _RoleDetail(
                              key: ValueKey('detail-${_selected!.name}'),
                              role: _selected!,
                              accent: _accent,
                            ),
                    ),
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  IgnorePointer(
                    ignoring: !hasSelection,
                    child: AnimatedOpacity(
                      duration: _animDuration,
                      curve: _animCurve,
                      opacity: hasSelection ? 1.0 : 0.0,
                      child: _ContinueButton(
                        accent: _accent,
                        onPressed: _continue,
                      ),
                    ),
                  ),
                  if (!widget.isSignIn) ...[
                    const SizedBox(height: MyShopSpacing.sm),
                    _SignInLink(
                      onTap: () => context.go('/signin/phone'),
                      color: hasSelection
                          ? Colors.white
                          : MyShopColors.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selectedRole,
    required this.title,
    required this.tagline,
    required this.icon,
    required this.accent,
    required this.assetPath,
    required this.onTap,
  });

  final ProviderType role;
  final ProviderType? selectedRole;
  final String title;
  final String tagline;
  final IconData icon;
  final Color accent;
  final String assetPath;
  final VoidCallback onTap;

  static const _animDuration = Duration(milliseconds: 380);
  static const _animCurve = Curves.easeOutCubic;
  static const _radius = 20.0;

  @override
  Widget build(BuildContext context) {
    final selected = selectedRole == role;
    final hasOther = selectedRole != null && !selected;

    final overlayColors = selected
        ? [accent.withValues(alpha: 0.35), accent.withValues(alpha: 0.85)]
        : [
            Colors.black.withValues(alpha: 0.20),
            Colors.black.withValues(alpha: 0.55),
          ];

    return AnimatedScale(
      duration: _animDuration,
      curve: _animCurve,
      scale: hasOther ? 0.94 : 1.0,
      child: AnimatedOpacity(
        duration: _animDuration,
        curve: _animCurve,
        opacity: hasOther ? 0.65 : 1.0,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(_radius),
            child: AnimatedContainer(
              duration: _animDuration,
              curve: _animCurve,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.32),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: MyShopColors.darkText.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(assetPath, fit: BoxFit.cover),
                    AnimatedContainer(
                      duration: _animDuration,
                      curve: _animCurve,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: overlayColors,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: MyShopSpacing.lg,
                        horizontal: MyShopSpacing.md,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.25),
                                  ),
                                ),
                                child:
                                    Icon(icon, size: 30, color: Colors.white),
                              ),
                              const Spacer(),
                              _SelectedBadge(visible: selected),
                            ],
                          ),
                          const SizedBox(height: MyShopSpacing.md),
                          Text(
                            title,
                            style: MyShopTypography.h2.copyWith(
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tagline,
                            style: MyShopTypography.body2.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      duration: const Duration(milliseconds: 380),
      curve: Curves.elasticOut,
      scale: visible ? 1 : 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: visible ? 1 : 0,
        child: Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 18,
            color: MyShopColors.success,
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              shape: BoxShape.circle,
              border: Border.all(
                color: MyShopColors.primaryGold.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.touch_app_rounded,
              color: MyShopColors.primaryGoldDark,
            ),
          ),
          const SizedBox(height: MyShopSpacing.md),
          Text(
            'Tap a card to continue',
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Each role stays separate, even when it uses the same phone number.',
            textAlign: TextAlign.center,
            style: MyShopTypography.caption,
          ),
        ],
      ),
    );
  }
}

class _RoleDetail extends StatelessWidget {
  const _RoleDetail({
    super.key,
    required this.role,
    required this.accent,
  });

  final ProviderType role;
  final Color accent;

  static const _driverFeatures = [
    ('Live navigation', Icons.navigation_rounded),
    ('Surge pricing alerts', Icons.trending_up_rounded),
    ('Earnings and payout status', Icons.payments_rounded),
  ];

  static const _artisanFeatures = [
    ('Bid on jobs in your trade', Icons.gavel_rounded),
    ('In-app chat with clients', Icons.chat_bubble_outline_rounded),
    ('Earnings and payout status', Icons.payments_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final features = role.isDriver ? _driverFeatures : _artisanFeatures;
    final perks = role.isDriver
        ? "You'll see ride requests near you the moment you go online."
        : "You'll see job requests for your trades the moment you go online.";

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.surfaceWhite,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: MyShopColors.divider),
          boxShadow: [
            BoxShadow(
              color: MyShopColors.darkText.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    role.isDriver
                        ? Icons.directions_car_filled_rounded
                        : Icons.handyman_rounded,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Text(
                    role.isDriver ? "What you'll do" : "What you'll do",
                    style: MyShopTypography.h3,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.sm),
            Text(perks, style: MyShopTypography.body2),
            const SizedBox(height: MyShopSpacing.md),
            for (final f in features) ...[
              _FeatureRow(label: f.$1, icon: f.$2, accent: accent),
              const SizedBox(height: MyShopSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.label,
    required this.icon,
    required this.accent,
  });

  final String label;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: accent),
        ),
        const SizedBox(width: MyShopSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignInLink extends StatelessWidget {
  const _SignInLink({required this.onTap, required this.color});

  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: MyShopSpacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account? ',
              style: MyShopTypography.body2.copyWith(
                color: color.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              'Sign in',
              style: MyShopTypography.body2.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.accent, required this.onPressed});

  final Color accent;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue',
                  style: MyShopTypography.button.copyWith(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: MyShopSpacing.sm),
                const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
