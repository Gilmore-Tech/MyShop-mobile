import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../auth/providers/auth_controller.dart';

/// Animated splash shown while the auth controller bootstraps from secure
/// storage. The GoRouter redirect callback takes over routing once
/// `bootstrap()` resolves (auth → role-aware home, unauth → onboarding /
/// sign-in). We just need to look on-brand during the ~1–2s warmup.
///
/// Mirrors the client app's splash pattern: one [AnimationController] drives
/// four staged entrance animations via [Interval] sub-curves.
class ProviderSplashScreen extends ConsumerStatefulWidget {
  const ProviderSplashScreen({super.key});

  @override
  ConsumerState<ProviderSplashScreen> createState() =>
      _ProviderSplashScreenState();
}

class _ProviderSplashScreenState extends ConsumerState<ProviderSplashScreen>
    with SingleTickerProviderStateMixin {
  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFF0F1923); // rich dark navy
  static const _gold = MyShopColors.primaryGold;

  // ── Animation ──────────────────────────────────────────────────────────────
  // Total controller duration: 1 400 ms
  //   Stage 1  0 %– 45 % (0–630 ms)  : logo mark  — scale + fade in
  //   Stage 2 30 %– 65 % (420–910 ms): wordmark    — slide up + fade in
  //   Stage 3 55 %– 80 % (770–1120 ms): tagline    — fade in
  //   Stage 4 72 %–100 % (1008–1400 ms): footer    — fade in
  static const _totalDuration = Duration(milliseconds: 1400);

  late final AnimationController _ctrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _wordSlide;
  late final Animation<double> _wordFade;
  late final Animation<double> _taglineFade;
  late final Animation<double> _footerFade;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ));

    _ctrl = AnimationController(vsync: this, duration: _totalDuration);

    final curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);

    _logoScale = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: curve, curve: const Interval(0.0, 0.45)),
    );
    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: curve, curve: const Interval(0.0, 0.40)),
    );
    _wordSlide = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(parent: curve, curve: const Interval(0.30, 0.65)),
    );
    _wordFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: curve, curve: const Interval(0.30, 0.65)),
    );
    _taglineFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: curve, curve: const Interval(0.55, 0.80)),
    );
    _footerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: curve, curve: const Interval(0.72, 1.0)),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final authState = ref.watch(authControllerProvider);
    final pending = authState is AuthSessionRestorePending ? authState : null;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Bottom gold accent bar.
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: h * 0.004,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, _gold, Colors.transparent],
                ),
              ),
            ),
          ),

          // Main centred content.
          Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: _LogoMark(w: w),
                    ),
                  ),
                  SizedBox(height: h * 0.028),
                  FadeTransition(
                    opacity: _wordFade,
                    child: Transform.translate(
                      offset: Offset(0, _wordSlide.value),
                      child: _Wordmark(w: w),
                    ),
                  ),
                  SizedBox(height: h * 0.012),
                  FadeTransition(
                    opacity: _taglineFade,
                    child: _Tagline(w: w),
                  ),
                ],
              ),
            ),
          ),

          // Loading dots + footer.
          Positioned(
            bottom: h * 0.07,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _footerFade,
              builder: (_, __) => Opacity(
                opacity: _footerFade.value,
                child: pending == null
                    ? Column(
                        children: [
                          _LoadingDots(w: w),
                          SizedBox(height: h * 0.022),
                          _Footer(w: w),
                        ],
                      )
                    : _SessionRestorePanel(
                        width: w,
                        state: pending,
                        onRetry: () => ref
                            .read(authControllerProvider.notifier)
                            .retrySessionRestore(),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SessionRestorePanel extends StatelessWidget {
  const _SessionRestorePanel({
    required this.width,
    required this.state,
    required this.onRetry,
  });

  final double width;
  final AuthSessionRestorePending state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Session recovery',
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: width * 0.1),
        child: Column(
          children: [
            Text(
              'Connect to the internet and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: width * 0.04,
              ),
            ),
            SizedBox(height: width * 0.04),
            FilledButton.icon(
              key: const ValueKey('retry_saved_session'),
              onPressed: state.isRetrying ? null : onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: MyShopColors.primaryGold,
                foregroundColor: const Color(0xFF0F1923),
                minimumSize: Size(width * 0.52, 48),
              ),
              icon: state.isRetrying
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(state.isRetrying ? 'Reconnecting…' : 'Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  final double w;
  const _LogoMark({required this.w});

  @override
  Widget build(BuildContext context) {
    final size = w * 0.32;
    return Image.asset(
      'assets/images/myshop_provider_logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      // Fall back to a gold square with a wrench icon if the asset isn't
      // bundled yet — keeps the splash looking intentional during the gap
      // between wiring the screen and dropping in the real logo file.
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: MyShopColors.primaryGold,
          borderRadius: BorderRadius.circular(size * 0.22),
        ),
        child: Icon(
          Icons.handyman_rounded,
          color: Colors.white,
          size: size * 0.5,
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  final double w;
  const _Wordmark({required this.w});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'My',
            style: TextStyle(
              color: Colors.white,
              fontSize: w * 0.092,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          TextSpan(
            text: 'Shop',
            style: TextStyle(
              color: MyShopColors.primaryGold,
              fontSize: w * 0.092,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tagline extends StatelessWidget {
  final double w;
  const _Tagline({required this.w});

  @override
  Widget build(BuildContext context) {
    final tagStyle = TextStyle(
      color: Colors.white.withAlpha(180),
      fontSize: w * 0.034,
      letterSpacing: 0.4,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Drive', style: tagStyle),
        SizedBox(width: w * 0.024),
        Text('·', style: tagStyle),
        SizedBox(width: w * 0.024),
        Text('Build', style: tagStyle),
        SizedBox(width: w * 0.024),
        Text('·', style: tagStyle),
        SizedBox(width: w * 0.024),
        Text('Earn', style: tagStyle),
      ],
    );
  }
}

/// Three animated pulsing dots — indicates app is initialising.
class _LoadingDots extends StatefulWidget {
  final double w;
  const _LoadingDots({required this.w});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_ctrl.value - i * 0.22).clamp(0.0, 1.0);
          final scale = 0.6 + 0.4 * _pulse(t);
          final opacity = 0.3 + 0.7 * _pulse(t);
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.w * 0.012),
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.w * 0.022,
                  height: widget.w * 0.022,
                  decoration: const BoxDecoration(
                    color: MyShopColors.primaryGold,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  /// Bell-curve pulse: 0→1→0 over the interval [0, 1].
  double _pulse(double t) {
    if (t <= 0 || t >= 1) return 0;
    return (1 - (2 * t - 1) * (2 * t - 1)).clamp(0.0, 1.0);
  }
}

class _Footer extends StatelessWidget {
  final double w;
  const _Footer({required this.w});

  @override
  Widget build(BuildContext context) {
    return Text(
      'Powered by Gilmore Technologies',
      style: TextStyle(
        color: Colors.white.withAlpha(60),
        fontSize: w * 0.028,
        letterSpacing: 0.3,
      ),
    );
  }
}
