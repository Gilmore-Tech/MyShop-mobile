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

  // Slate background color used when the driver theme is active.
  static const _slateBgTop = Color(0xFFE6ECF1);

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
      context.go(role.isDriver ? '/signup/driver' : '/signup/artisan');
    }
  }

  Color get _accent => switch (_selected) {
        ProviderType.driver => MyShopColors.darkSlate,
        ProviderType.artisan => MyShopColors.primaryGoldDark,
        null => MyShopColors.primaryGold,
      };

  LinearGradient get _backgroundGradient => switch (_selected) {
        ProviderType.driver => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_slateBgTop, MyShopColors.surfaceWhite],
            stops: [0, 0.55],
          ),
        ProviderType.artisan => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [MyShopColors.primaryGoldLight, MyShopColors.surfaceWhite],
            stops: [0, 0.55],
          ),
        null => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [MyShopColors.offWhite, MyShopColors.surfaceWhite],
            stops: [0, 0.55],
          ),
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
            : 'Quick rides, live navigation, and fares paid the moment a trip ends.',
        ProviderType.artisan => widget.isSignIn
            ? "We'll send a code to your registered phone number."
            : 'Win jobs in your trade, bid on requests, and get paid the moment a job is done.',
        null => widget.isSignIn
            ? 'Select your account type to continue.'
            : 'Choose the type of account you want to create. You can only have one role per phone number.',
      };

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selected != null;

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: AnimatedContainer(
        duration: _animDuration,
        curve: _animCurve,
        decoration: BoxDecoration(gradient: _backgroundGradient),
        child: SafeArea(
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
                      Text(_headline, style: MyShopTypography.h1),
                      const SizedBox(height: MyShopSpacing.sm),
                      Text(_subhead, style: MyShopTypography.body2),
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
              ],
            ),
          ),
        ),
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
    required this.onTap,
  });

  final ProviderType role;
  final ProviderType? selectedRole;
  final String title;
  final String tagline;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  static const _animDuration = Duration(milliseconds: 380);
  static const _animCurve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final selected = selectedRole == role;
    final hasOther = selectedRole != null && !selected;

    final bgColor = selected ? accent : MyShopColors.surfaceWhite;
    final borderColor = selected ? accent : MyShopColors.divider;
    final iconBg = selected
        ? Colors.white.withValues(alpha: 0.18)
        : accent.withValues(alpha: 0.10);
    final iconColor = selected ? Colors.white : accent;
    final titleColor = selected ? Colors.white : MyShopColors.textPrimary;
    final taglineColor = selected
        ? Colors.white.withValues(alpha: 0.85)
        : MyShopColors.textSecondary;

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
            borderRadius: BorderRadius.circular(20),
            child: AnimatedContainer(
              duration: _animDuration,
              curve: _animCurve,
              padding: const EdgeInsets.symmetric(
                vertical: MyShopSpacing.lg,
                horizontal: MyShopSpacing.md,
              ),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor, width: selected ? 0 : 1),
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: _animDuration,
                        curve: _animCurve,
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(icon, size: 30, color: iconColor),
                      ),
                      const Spacer(),
                      _SelectedBadge(visible: selected),
                    ],
                  ),
                  const SizedBox(height: MyShopSpacing.md),
                  AnimatedDefaultTextStyle(
                    duration: _animDuration,
                    curve: _animCurve,
                    style: MyShopTypography.h2.copyWith(color: titleColor),
                    child: Text(title),
                  ),
                  const SizedBox(height: 2),
                  AnimatedDefaultTextStyle(
                    duration: _animDuration,
                    curve: _animCurve,
                    style: MyShopTypography.body2.copyWith(color: taglineColor),
                    child: Text(tagline),
                  ),
                ],
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
            'You can change your role only by creating a new account.',
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
    ('Instant MoMo payouts', Icons.payments_rounded),
  ];

  static const _artisanFeatures = [
    ('Bid on jobs in your trade', Icons.gavel_rounded),
    ('In-app chat with clients', Icons.chat_bubble_outline_rounded),
    ('Instant MoMo payouts', Icons.payments_rounded),
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
