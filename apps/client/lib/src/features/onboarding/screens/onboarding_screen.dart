import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../app/router.dart' show AppRoutes;
import '../../auth/providers/auth_controller.dart';
import '../../profile/providers/app_preferences_provider.dart';

// ── Onboarding ────────────────────────────────────────────────────────────────
//
// Four-page intro carousel that teaches first-time clients (and anyone who
// flips the "Replay Onboarding" preference) how MyShop works. Pages are short
// — title, one-sentence description, a single illustrative icon — so the
// user can swipe through in under 30 seconds.
//
// Completion side-effects:
//   1. tokenStorage.markOnboardingSeen()  → sticky flag, persists across logout
//   2. appPreferencesProvider.toggleReplayOnboarding(false)
//      → if the user got here via replay, clear the one-shot flag so the
//        next app open lands on home instead of replaying again
//   3. context.go(AppRoutes.home)
//
// The router redirect gates entry to this screen on
// `!hasSeenOnboarding || replayOnboarding`, so the user only sees it when
// it's actually meant to play.

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int  _index = 0;
  bool _isFinishing = false;

  static const _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.waving_hand_outlined,
      iconColor: MyShopColors.primaryGold,
      title: 'Welcome to MyShop',
      body: "Ghana's all-in-one marketplace for instant rides and trusted "
          'artisans. Built for the way you actually move and work.',
    ),
    _OnboardingPage(
      icon: Icons.directions_car_filled_outlined,
      iconColor: MyShopColors.primaryGold,
      title: 'Book rides in seconds',
      body: 'Tap a destination, see the fare upfront, and watch your driver '
          "arrive on the map. We don't surprise you at drop-off.",
    ),
    _OnboardingPage(
      icon: Icons.handyman_outlined,
      iconColor: MyShopColors.primaryGold,
      title: 'Hire verified artisans',
      body: 'Plumbers, electricians, mechanics — vetted and rated. Compare '
          'bids, chat in-app, and only release payment once the job is done.',
    ),
    _OnboardingPage(
      icon: Icons.verified_user_outlined,
      iconColor: MyShopColors.success,
      title: 'Pay securely, every time',
      body: 'Mobile Money or card — your money sits in escrow until you '
          'confirm the work. Receipts and history live in the Activity tab.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLastPage => _index == _pages.length - 1;

  Future<void> _finish() async {
    if (_isFinishing || !mounted) return;
    setState(() => _isFinishing = true);

    // Sticky flag — user has now seen it at least once.
    await ref.read(tokenStorageProvider).markOnboardingSeen();
    if (!mounted) return;

    // Reflect that in memory so the router redirect lets us through.
    ref.read(hasSeenOnboardingProvider.notifier).state = true;

    // One-shot replay flag — clear both the SharedPrefs key (via the
    // preferences notifier) and the top-level mirror that the router
    // watches. If we only cleared SharedPrefs, the router would still
    // see pendingReplay == true and bounce us back here.
    await ref
        .read(appPreferencesProvider.notifier)
        .toggleReplayOnboarding(false);
    ref.read(pendingReplayOnboardingProvider.notifier).state = false;
    if (!mounted) return;

    context.go(AppRoutes.home);
  }

  void _goToPage(int next) {
    if (next < 0 || next >= _pages.length) return;
    _pageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 280),
      curve:    Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final size  = MediaQuery.sizeOf(context);
    final w     = size.width;
    final h     = size.height;
    final inset = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar: skip ──
            Padding(
              padding: EdgeInsets.fromLTRB(
                  w * 0.044, h * 0.012, w * 0.044, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!_isLastPage)
                    TextButton(
                      onPressed: _isFinishing ? null : _finish,
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.025,
                          vertical:   h * 0.008,
                        ),
                      ),
                      child: Text(
                        'Skip',
                        style: TextStyle(
                          fontFamily:    'Raleway',
                          fontSize:      w * 0.038,
                          fontWeight:    FontWeight.w600,
                          color:         MyShopColors.textSecondary,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // ── Pages ──
            Expanded(
              child: PageView.builder(
                controller:  _pageController,
                itemCount:   _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _PageView(page: _pages[i], w: w, h: h),
              ),
            ),

            // ── Dots ──
            Padding(
              padding: EdgeInsets.symmetric(vertical: h * 0.018),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    _Dot(active: i == _index, w: w),
                ],
              ),
            ),

            // ── Bottom bar: back + primary CTA ──
            Padding(
              padding: EdgeInsets.fromLTRB(
                w * 0.044,
                0,
                w * 0.044,
                inset.bottom + h * 0.018,
              ),
              child: Row(
                children: [
                  if (_index > 0)
                    _GhostButton(
                      label: 'Back',
                      onPressed: _isFinishing
                          ? null
                          : () => _goToPage(_index - 1),
                      w: w,
                      h: h,
                    )
                  else
                    SizedBox(width: w * 0.220),
                  const Spacer(),
                  _PrimaryButton(
                    label: _isLastPage ? "I'm ready" : 'Next',
                    isLoading: _isFinishing,
                    onPressed: _isFinishing
                        ? null
                        : (_isLastPage ? _finish : () => _goToPage(_index + 1)),
                    w: w,
                    h: h,
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

// ── Page model + view ─────────────────────────────────────────────────────────

class _OnboardingPage {
  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   body;

  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });
}

class _PageView extends StatelessWidget {
  final _OnboardingPage page;
  final double          w, h;
  const _PageView({required this.page, required this.w, required this.h});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: w * 0.072,
        vertical:   h * 0.020,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Hero icon block
          Container(
            width:  w * 0.46,
            height: w * 0.46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end:   Alignment.bottomRight,
                colors: [
                  page.iconColor.withValues(alpha: 0.16),
                  page.iconColor.withValues(alpha: 0.04),
                ],
              ),
              borderRadius: BorderRadius.circular(w * 0.10),
              border: Border.all(
                color: page.iconColor.withValues(alpha: 0.28),
                width: 1.5,
              ),
            ),
            child: Icon(
              page.icon,
              size:  w * 0.20,
              color: page.iconColor,
            ),
          ),
          SizedBox(height: h * 0.046),

          Text(
            page.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily:    'Raleway',
              fontSize:      w * 0.062,
              fontWeight:    FontWeight.w800,
              color:         MyShopColors.textPrimary,
              height:        1.2,
              letterSpacing: -0.3,
            ),
          ),
          SizedBox(height: h * 0.018),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Raleway',
              fontSize:   w * 0.038,
              fontWeight: FontWeight.w400,
              color:      MyShopColors.textSecondary,
              height:     1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Dot indicator ─────────────────────────────────────────────────────────────

class _Dot extends StatelessWidget {
  final bool   active;
  final double w;
  const _Dot({required this.active, required this.w});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:  const Duration(milliseconds: 220),
      curve:     Curves.easeInOut,
      width:     active ? w * 0.062 : w * 0.020,
      height:    w * 0.020,
      margin:    EdgeInsets.symmetric(horizontal: w * 0.008),
      decoration: BoxDecoration(
        color: active ? MyShopColors.primaryGold : MyShopColors.divider,
        borderRadius: BorderRadius.circular(w * 0.020),
      ),
    );
  }
}

// ── Buttons ───────────────────────────────────────────────────────────────────

class _PrimaryButton extends StatelessWidget {
  final String        label;
  final bool          isLoading;
  final VoidCallback? onPressed;
  final double        w, h;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: h * 0.062,
      width:  w * 0.420,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MyShopColors.darkSlate,
          foregroundColor: MyShopColors.surfaceWhite,
          disabledBackgroundColor: MyShopColors.surfaceGrey,
          disabledForegroundColor: MyShopColors.disabled,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(w * 0.022),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width:  w * 0.046,
                height: w * 0.046,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: MyShopColors.surfaceWhite,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily:    'Raleway',
                      fontSize:      w * 0.040,
                      fontWeight:    FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  SizedBox(width: w * 0.015),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: w * 0.046,
                  ),
                ],
              ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String        label;
  final VoidCallback? onPressed;
  final double        w, h;

  const _GhostButton({
    required this.label,
    required this.onPressed,
    required this.w,
    required this.h,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: h * 0.062,
      width:  w * 0.220,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(w * 0.022),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily:    'Raleway',
            fontSize:      w * 0.038,
            fontWeight:    FontWeight.w600,
            color:         MyShopColors.textSecondary,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
