import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

// ── SplashScreen ──────────────────────────────────────────────────────────────
// PRD § 4.1: On launch, check for a valid JWT in secure storage.
// If found  → navigate to /home (auto-login).
// If absent → navigate to /welcome (first-time / logged-out).
//
// This screen uses a single AnimationController driving all entrance stages via
// Interval sub-animations.  StatefulWidget is permitted here (animation only).

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  // ── Design tokens ──────────────────────────────────────────────────────────
  static const _bg   = Color(0xFF0F1923); // rich dark navy
  static const _gold = MyShopColors.primaryGold;

  // ── Animation ──────────────────────────────────────────────────────────────
  // Total controller duration: 1 400 ms
  //   Stage 1  0 %– 45 % (0–630 ms)  : logo mark  — scale + fade in
  //   Stage 2 30 %– 65 % (420–910 ms): wordmark    — slide up + fade in
  //   Stage 3 55 %– 80 % (770–1120 ms): tagline    — fade in
  //   Stage 4 72 %–100 % (1008–1400 ms): footer    — fade in
  // Hold 600 ms then navigate → total visible ~2 000 ms (well under 3 s target)

  static const _totalDuration = Duration(milliseconds: 1400);

  late final AnimationController _ctrl;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _wordSlide;  // translateY offset: 24 → 0
  late final Animation<double> _wordFade;
  late final Animation<double> _taglineFade;
  late final Animation<double> _footerFade;

  @override
  void initState() {
    super.initState();

    // Force transparent status bar so splash fills the notch area.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ));

    _ctrl = AnimationController(vsync: this, duration: _totalDuration)
      ..addStatusListener(_onAnimationStatus);

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

  void _onAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      Future.delayed(const Duration(milliseconds: 600), _navigate);
    }
  }

  void _navigate() {
    if (!mounted) return;
    // The GoRouter redirect callback handles routing based on auth state.
    // By the time the splash animation finishes (~2s), bootstrap() has
    // resolved and the auth state is either Authenticated or Unauthenticated.
    // GoRouter's refreshListenable fires the redirect automatically.
    // No explicit navigation needed — just stay put and let the redirect work.
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // ── Background radial glow behind logo ──────────────────────────
          Positioned(
            top: h * 0.22,
            left: w * 0.5 - w * 0.38,
            child: _RadialGlow(size: w * 0.76),
          ),

          // ── Bottom gold accent bar ──────────────────────────────────────
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

          // ── Main centred content ────────────────────────────────────────
          Center(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo mark
                  FadeTransition(
                    opacity: _logoFade,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: _LogoMark(w: w),
                    ),
                  ),

                  SizedBox(height: h * 0.028),

                  // Wordmark
                  FadeTransition(
                    opacity: _wordFade,
                    child: Transform.translate(
                      offset: Offset(0, _wordSlide.value),
                      child: _Wordmark(w: w),
                    ),
                  ),

                  SizedBox(height: h * 0.012),

                  // Tagline
                  FadeTransition(
                    opacity: _taglineFade,
                    child: _Tagline(w: w),
                  ),
                ],
              ),
            ),
          ),

          // ── DEV shortcut ───────────────────────────────────────────────
          Positioned(
            bottom: h * 0.015,
            right:  w * 0.041,
            child: GestureDetector(
              onTap: () {
                _ctrl.stop();
                context.go('/dev');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        Colors.white.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withAlpha(40)),
                ),
                child: Text(
                  'DEV',
                  style: TextStyle(
                    fontSize:      w * 0.026,
                    fontWeight:    FontWeight.w900,
                    color:         Colors.white.withAlpha(120),
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ),
          ),

          // ── Loading dots + footer ───────────────────────────────────────
          Positioned(
            bottom: h * 0.07,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _footerFade,
              builder: (_, __) => Opacity(
                opacity: _footerFade.value,
                child: Column(
                  children: [
                    _LoadingDots(w: w),
                    SizedBox(height: h * 0.022),
                    _Footer(w: w),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _RadialGlow extends StatelessWidget {
  final double size;
  const _RadialGlow({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            MyShopColors.primaryGold.withAlpha(30),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  final double w;
  const _LogoMark({required this.w});

  static const _gold     = MyShopColors.primaryGold;
  static const _goldDark = MyShopColors.primaryGoldDark;

  @override
  Widget build(BuildContext context) {
    final size = w * 0.26;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_gold, _goldDark],
        ),
        boxShadow: [
          BoxShadow(
            color: _gold.withAlpha(100),
            blurRadius: w * 0.10,
            spreadRadius: w * 0.01,
          ),
        ],
      ),
      child: Center(
        child: _ShoppingBagIcon(size: size * 0.52),
      ),
    );
  }
}

/// Custom shopping bag icon built from Flutter primitives.
class _ShoppingBagIcon extends StatelessWidget {
  final double size;
  const _ShoppingBagIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _BagPainter(),
    );
  }
}

class _BagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Bag body — rounded rectangle, bottom 72 % of height
    final bodyTop = h * 0.30;
    final bodyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.08, bodyTop, w * 0.84, h * 0.64),
      Radius.circular(w * 0.12),
    );
    canvas.drawRRect(bodyRect, paint);

    // Handle cut-out — oval hole at top of body
    final cutoutPaint = Paint()
      ..color = MyShopColors.primaryGoldDark  // matches logo gradient end
      ..style = PaintingStyle.fill;
    final handlePath = Path()
      ..addOval(Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.31),
        width:  w * 0.42,
        height: h * 0.22,
      ));
    canvas.drawPath(handlePath, cutoutPaint);

    // Handle stroke — white arc above body
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.28),
        width:  w * 0.48,
        height: h * 0.38,
      ),
      3.14159,   // π — start at left (180°)
      3.14159,   // π — sweep to right (360°)
      false,
      strokePaint,
    );
  }

  @override
  bool shouldRepaint(_BagPainter old) => false;
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TagDot(w: w),
        SizedBox(width: w * 0.018),
        Text(
          'Rides',
          style: TextStyle(
            color: Colors.white.withAlpha(180),
            fontSize: w * 0.034,
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(width: w * 0.018),
        _TagDot(w: w),
        SizedBox(width: w * 0.018),
        Text(
          'Services',
          style: TextStyle(
            color: Colors.white.withAlpha(180),
            fontSize: w * 0.034,
            letterSpacing: 0.4,
          ),
        ),
        SizedBox(width: w * 0.018),
        _TagDot(w: w),
        SizedBox(width: w * 0.018),
        Text(
          'Delivered',
          style: TextStyle(
            color: Colors.white.withAlpha(180),
            fontSize: w * 0.034,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _TagDot extends StatelessWidget {
  final double w;
  const _TagDot({required this.w});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: w * 0.012,
      height: w * 0.012,
      decoration: const BoxDecoration(
        color: MyShopColors.primaryGold,
        shape: BoxShape.circle,
      ),
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
          // Stagger: dot i starts at i*0.2 of the cycle
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
                  width:  widget.w * 0.022,
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
