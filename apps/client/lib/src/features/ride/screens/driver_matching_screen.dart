import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ride_tracking_screen.dart';

// ─── Design Tokens ─────────────────────────────────────────────────────────────
// Source: CLAUDE.md §5.2
const _kGold = Color(0xFFF5A623);
const _kDarkSlate = Color(0xFF46535D);
const _kDarkText = Color(0xFF161A1D);
const _kTextSecondary = Color(0xFF555E68);
const _kSurfaceGrey = Color(0xFFF3F5F6);
const _kError = Color(0xFFEB5757);
const _kMapBg = Color(0xFFE3E3E3);
const _kOffWhite = Color(0xFFF6F7F8);
const _kSuccess = Color(0xFF27AE60);

// ─── State Enum ───────────────────────────────────────────────────────────────

enum _MatchState { searching, found, notFound }

// ─── Screen ───────────────────────────────────────────────────────────────────

/// Driver matching screen — three states driven by WebSocket in Phase 2.
///
/// searching → [driver accepts] → found
/// searching → [timeout/no drivers] → notFound
///
/// PRD §4.3 | EDD §4: POST /v1/rides, WebSocket ws://api/v1/rides/:id/live
/// Initial radius: 3 km, expands in 2 km increments up to 10 km (EDD config).
class DriverMatchingScreen extends ConsumerStatefulWidget {
  const DriverMatchingScreen({super.key});

  @override
  ConsumerState<DriverMatchingScreen> createState() =>
      _DriverMatchingScreenState();
}

class _DriverMatchingScreenState extends ConsumerState<DriverMatchingScreen>
    with SingleTickerProviderStateMixin {
  _MatchState _state = _MatchState.searching;
  int _countdown = 45;

  Timer? _countdownTimer;
  Timer? _demoTimer; // Remove when WebSocket subscription is wired (EDD §4)

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _startTimers();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _demoTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  // ── Timer management ───────────────────────────────────────────────────────

  void _startTimers() {
    _countdownTimer?.cancel();
    _demoTimer?.cancel();

    // Countdown tick — expires → notFound
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 1) {
        t.cancel();
        if (_state == _MatchState.searching) {
          _pulseController.stop();
          setState(() => _state = _MatchState.notFound);
        }
      } else {
        setState(() => _countdown--);
      }
    });

    // Demo: simulate driver acceptance after 8 s — remove when WebSocket wired
    _demoTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted || _state != _MatchState.searching) return;
      _countdownTimer?.cancel();
      setState(() => _state = _MatchState.found);
    });
  }

  void _retry() {
    if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
    setState(() {
      _state = _MatchState.searching;
      _countdown = 45;
    });
    _startTimers();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _countdownText {
    final m = _countdown ~/ 60;
    final s = _countdown % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Driver accepted — hand off to full detail screen
    if (_state == _MatchState.found) {
      return _DriverFoundView(
        onConfirm: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const RideTrackingScreen(),
            ),
          );
        },
        onCancel: () => Navigator.pop(context),
      );
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final circleDiameter = screenWidth * 0.80;

    return Scaffold(
      backgroundColor: _kMapBg,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Map background
                const ColoredBox(color: _kMapBg),

                // Search radius circle (pulsing when searching)
                _RadiusCircle(
                  state: _state,
                  diameter: circleDiameter,
                  pulseAnimation: _pulseAnimation,
                ),

                // Location pin — searching & found
                if (_state != _MatchState.notFound)
                  const Center(child: _LocationPin()),

                // Driver car markers — found only
                if (_state == _MatchState.found) ...[
                  const Align(
                    alignment: Alignment(0.08, -0.42),
                    child: _CarMarker(highlighted: true),
                  ),
                  const Align(
                    alignment: Alignment(0.80, 0.10),
                    child: _CarMarker(highlighted: false),
                  ),
                  const Align(
                    alignment: Alignment(-0.64, 0.46),
                    child: _CarMarker(highlighted: false),
                  ),
                ],

                // Error illustration — notFound only
                if (_state == _MatchState.notFound)
                  const Center(child: _NotFoundIllustration()),

                // Top badge / pill
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: switch (_state) {
                        _MatchState.searching => const _SearchingPill(),
                        _MatchState.found => const _DriversAvailableBadge(count: 3),
                        _MatchState.notFound => const SizedBox.shrink(),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sticky bottom panel — swaps per state
          switch (_state) {
            _MatchState.searching =>
              _SearchingBottomPanel(countdown: _countdownText),
            _MatchState.found => const _FoundBottomPanel(),
            _MatchState.notFound => _NotFoundBottomPanel(
                onRetry: _retry,
                onExpand: () {
                  // TODO(MSP-XX): PATCH /v1/rides/:id with expanded radius
                  _retry();
                },
              ),
          },
        ],
      ),
    );
  }
}

// ─── Radius Circle ────────────────────────────────────────────────────────────

class _RadiusCircle extends StatelessWidget {
  const _RadiusCircle({
    required this.state,
    required this.diameter,
    required this.pulseAnimation,
  });

  final _MatchState state;
  final double diameter;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    final isNotFound = state == _MatchState.notFound;
    return Center(
      child: AnimatedBuilder(
        animation: pulseAnimation,
        builder: (_, __) => Transform.scale(
          scale: state == _MatchState.searching ? pulseAnimation.value : 1.0,
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNotFound
                  ? const Color(0xFFBBBBBB).withAlpha(90)
                  : const Color(0xFFD4B896).withAlpha(140),
              border: Border.all(
                color: isNotFound ? const Color(0xFFAAAAAA) : _kGold,
                width: 2.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Map Widgets ──────────────────────────────────────────────────────────────

class _LocationPin extends StatelessWidget {
  const _LocationPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: const BoxDecoration(
            color: _kDarkSlate,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.location_on, color: Colors.white, size: 24),
        ),
        Container(width: 3, height: 14, color: _kDarkSlate),
      ],
    );
  }
}

class _CarMarker extends StatelessWidget {
  const _CarMarker({required this.highlighted});

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: highlighted ? _kGold : Colors.white,
        shape: BoxShape.circle,
        border: highlighted
            ? null
            : Border.all(color: const Color(0xFFDDDDDD), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.directions_car_outlined,
        size: 22,
        color: highlighted ? Colors.white : _kDarkSlate,
      ),
    );
  }
}

// ─── Top Badges ───────────────────────────────────────────────────────────────

class _SearchingPill extends StatelessWidget {
  const _SearchingPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_rounded, size: 18, color: _kDarkText),
          SizedBox(width: 8),
          Text(
            'Finding nearby drivers...',
            style: TextStyle(
              color: _kDarkText,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriversAvailableBadge extends StatelessWidget {
  const _DriversAvailableBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: _kGold,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(64),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Drivers available',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Not Found Illustration ───────────────────────────────────────────────────

class _NotFoundIllustration extends StatelessWidget {
  const _NotFoundIllustration();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Composite icon: dark location pin + red error circle overlapping below
          SizedBox(
            width: 80,
            height: 88,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                // Dark slate location pin
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: _kDarkSlate,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                // White circle with red "!" — overlaps lower portion of pin
                Positioned(
                  bottom: 0,
                  left: 14,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      color: _kError,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'No Drivers Found',
            style: TextStyle(
              color: _kDarkText,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "We couldn't find any drivers within 1.5km of your location.",
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 14,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Bottom Panels ────────────────────────────────────────────────────────────

class _SearchingBottomPanel extends StatelessWidget {
  const _SearchingBottomPanel({required this.countdown});

  final String countdown;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16, 18, 16, 18 + bottomPad),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.access_time_outlined,
              size: 24,
              color: _kDarkSlate,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Search expires in',
                  style: TextStyle(
                    color: _kDarkText,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Looking in 2km radius',
                  style: TextStyle(color: _kTextSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            countdown,
            style: const TextStyle(
              color: _kGold,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _FoundBottomPanel extends StatelessWidget {
  const _FoundBottomPanel();

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomPad),
      child: Row(
        children: [
          // Driver photo
          ClipOval(
            child: Image.network(
              'https://i.pravatar.cc/150?img=7',
              width: 54,
              height: 54,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 54,
                height: 54,
                color: _kSurfaceGrey,
                child: const Icon(Icons.person, size: 30, color: _kDarkSlate),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Driver info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Kofi Mensah',
                      style: TextStyle(
                        color: _kDarkText,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.star_border_rounded,
                      size: 16,
                      color: _kGold,
                    ),
                    const SizedBox(width: 2),
                    const Text(
                      '4.9',
                      style: TextStyle(
                        color: _kDarkText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  'Toyota Vitz • GW 204-22',
                  style: TextStyle(color: _kTextSecondary, fontSize: 12),
                ),
                const SizedBox(height: 4),
                const Row(
                  children: [
                    Icon(Icons.near_me_outlined, size: 13, color: _kGold),
                    SizedBox(width: 3),
                    Text(
                      '3 mins away',
                      style: TextStyle(
                        color: _kGold,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Accepted button
          ElevatedButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const RideTrackingScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kDarkSlate,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            ),
            child: const Text(
              'Accepted',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotFoundBottomPanel extends StatelessWidget {
  const _NotFoundBottomPanel({
    required this.onRetry,
    required this.onExpand,
  });

  final VoidCallback onRetry;
  final VoidCallback onExpand;

  static const _kRadii = ['2.5km', '5km', '10km'];

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Retry + Expand buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kDarkText,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFFDDDDDD)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onExpand,
                  icon: const Icon(Icons.open_in_full_rounded, size: 18),
                  label: const Text(
                    'Expand',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kDarkSlate,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Suggested radii
          const Text(
            'SUGGESTED RADII',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: _kDarkText,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: _kRadii
                .map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: onExpand,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _kSurfaceGrey,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          r,
                          style: const TextStyle(
                            color: _kDarkText,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ─── Driver Found View ────────────────────────────────────────────────────────

/// Full detail screen shown once a driver accepts.
/// PRD §4.3 — displays driver profile, vehicle info, upfront fare, and safety prompt.
/// EDD §4: fare breakdown from POST /v1/rides/estimate response.
class _DriverFoundView extends StatelessWidget {
  const _DriverFoundView({
    required this.onConfirm,
    required this.onCancel,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kOffWhite,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.white,
        leading: BackButton(color: _kDarkText),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Driver Found',
              style: TextStyle(
                color: _kDarkText,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _kSuccess,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                const Text(
                  'ACTIVE SEARCH',
                  style: TextStyle(
                    color: _kTextSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Colors.grey[200]!),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  _DriverHeroCard(),
                  SizedBox(height: 16),
                  _TripDetailsSection(),
                  SizedBox(height: 12),
                  _FareBreakdownCard(),
                  SizedBox(height: 12),
                  _SafetyCard(),
                  SizedBox(height: 8),
                ],
              ),
            ),
          ),
          _DriverFoundFooter(onConfirm: onConfirm, onCancel: onCancel),
        ],
      ),
    );
  }
}

// ─── Driver Hero Card ─────────────────────────────────────────────────────────

class _DriverHeroCard extends StatelessWidget {
  const _DriverHeroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          // Arrival headline
          const Text(
            'Kofi is arriving!',
            style: TextStyle(
              color: _kDarkText,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            "We've found a highly-rated driver near",
            style: TextStyle(color: _kTextSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const Text(
            'Kumasi Central Market.',
            style: TextStyle(
              color: _kGold,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Driver avatar with online indicator
          Stack(
            clipBehavior: Clip.none,
            children: [
              ClipOval(
                child: Image.network(
                  'https://i.pravatar.cc/150?img=52',
                  width: 84,
                  height: 84,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 84,
                    height: 84,
                    color: _kSurfaceGrey,
                    child: const Icon(Icons.person, size: 44, color: _kDarkSlate),
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _kSuccess,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Name
          const Text(
            'Kofi Mensah',
            style: TextStyle(
              color: _kDarkText,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          // Rating + trips
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star_border_rounded, size: 16, color: _kGold),
              SizedBox(width: 4),
              Text(
                '4.92',
                style: TextStyle(
                  color: _kDarkText,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                ' · 1,450 trips',
                style: TextStyle(color: _kTextSecondary, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Verified + Police Checked badges
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _DriverBadge(
                icon: Icons.verified_outlined,
                label: 'Verified',
                color: _kGold,
              ),
              SizedBox(width: 10),
              _DriverBadge(
                icon: Icons.security_outlined,
                label: 'Police Checked',
                color: _kDarkText,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Masked phone — backend masks all numbers (CLAUDE.md §8.4)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE0E0E0)),
              borderRadius: BorderRadius.circular(30),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_outlined, size: 16, color: _kDarkText),
                SizedBox(width: 8),
                Text(
                  '+233 ··· ··· 42',
                  style: TextStyle(
                    color: _kDarkText,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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

class _DriverBadge extends StatelessWidget {
  const _DriverBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        border: Border.all(color: color.withAlpha(80)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trip Details ─────────────────────────────────────────────────────────────

class _TripDetailsSection extends StatelessWidget {
  const _TripDetailsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'TRIP DETAILS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            color: _kTextSecondary,
            letterSpacing: 1.4,
          ),
        ),
        SizedBox(height: 10),
        _VehicleCard(),
      ],
    );
  }
}

class _VehicleCard extends StatelessWidget {
  const _VehicleCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'VEHICLE',
                  style: TextStyle(
                    fontSize: 10,
                    color: _kTextSecondary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Midnight Black Toyota Camry Hybrid',
                  style: TextStyle(
                    color: _kDarkText,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Plate badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _kGold,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'GR-4567-23',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Text(
                      '3 mins away',
                      style: TextStyle(
                        color: _kDarkText,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.access_time, size: 13, color: _kGold),
                    const SizedBox(width: 3),
                    const Text(
                      'Est. Arrival',
                      style: TextStyle(color: _kGold, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Vehicle photo with ride class badge
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
            child: Stack(
              children: [
                Container(
                  height: 160,
                  width: double.infinity,
                  color: const Color(0xFF1C1C1E),
                  child: const Icon(
                    Icons.directions_car,
                    size: 80,
                    color: Color(0x33FFFFFF),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Premier Comfort',
                      style: TextStyle(
                        color: _kDarkText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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

// ─── Fare Breakdown ───────────────────────────────────────────────────────────

/// Upfront fare — calculated from POST /v1/rides/estimate (EDD §4).
/// base_fare + (distance_km × per_km_rate) + (duration_mins × per_min_rate)
class _FareBreakdownCard extends StatelessWidget {
  const _FareBreakdownCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          const _FareRow(label: 'Base Fare', value: 'GH₵ 12.00'),
          const SizedBox(height: 8),
          const _FareRow(label: 'Distance (5.2 km)', value: 'GH₵ 15.50'),
          const SizedBox(height: 8),
          const _FareRow(label: 'Booking Fee', value: 'GH₵ 2.50'),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF0F0F0)),
          ),
          const _FareRow(
            label: 'Total Upfront Fare',
            value: 'GH₵ 30.00',
            bold: true,
          ),
          const SizedBox(height: 10),
          const Text(
            'Includes all taxes and commissions. No hidden charges.',
            style: TextStyle(
              color: _kTextSecondary,
              fontSize: 11,
              fontStyle: FontStyle.italic,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  const _FareRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: bold ? _kDarkText : _kTextSecondary,
      fontSize: bold ? 14 : 13,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style.copyWith(color: _kDarkText)),
      ],
    );
  }
}

// ─── Safety Card ──────────────────────────────────────────────────────────────

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _kGold, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              color: Color(0x1AF5A623),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.security_outlined, color: _kGold, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  color: _kTextSecondary,
                  fontSize: 12,
                  height: 1.6,
                ),
                children: [
                  TextSpan(
                    text: 'Safety First: ',
                    style: TextStyle(
                      color: _kDarkText,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text:
                        'Please verify the vehicle plate and driver identity before entering the car. Share your trip status with friends.',
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

// ─── Driver Found Footer ──────────────────────────────────────────────────────

class _DriverFoundFooter extends StatelessWidget {
  const _DriverFoundFooter({
    required this.onConfirm,
    required this.onCancel,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Confirm Ride CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: onConfirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kDarkSlate,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'Confirm Ride',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Cancel — red, 3-min free window (EDD §4)
          GestureDetector(
            onTap: onCancel,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cancel_outlined, color: _kError, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Cancel Request',
                  style: TextStyle(
                    color: _kError,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 13, color: _kTextSecondary),
              SizedBox(width: 4),
              Text(
                'Free cancellation within 3 minutes of match.',
                style: TextStyle(color: _kTextSecondary, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
