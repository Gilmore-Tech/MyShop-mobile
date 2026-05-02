import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';

// ── Screen ─────────────────────────────────────────────────────────────────────
// PRD § 4.6 — Live artisan location tracking while en route to job site.
// Real-time updates via WS /v1/jobs/:id/live.
// Artisan's GPS position is broadcast every 5 s from the Provider app.

class JobTrackingScreen extends ConsumerWidget {
  const JobTrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final bot = MediaQuery.paddingOf(context).bottom;
    final jobId = GoRouterState.of(context).pathParameters['jobId'] ?? '';

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      body: Stack(
        children: [
          // Map placeholder
          _MapPlaceholder(h: h),

          // Top bar
          _TopBar(w: w, onBack: () => context.pop()),

          // Bottom sheet
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomSheet(
              w: w,
              h: h,
              bot: bot,
              jobId: jobId,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Map placeholder ────────────────────────────────────────────────────────────

class _MapPlaceholder extends StatelessWidget {
  final double h;
  const _MapPlaceholder({required this.h});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Container(
        color: const Color(0xFFE8EDF0),
        child: CustomPaint(painter: _GridPainter()),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD0D8DC)
      ..strokeWidth = 1;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Artisan dot
    final cx = size.width * 0.45;
    final cy = size.height * 0.42;
    canvas.drawCircle(
        Offset(cx, cy), 18, Paint()..color = MyShopColors.primaryGold);
    canvas.drawCircle(Offset(cx, cy), 10, Paint()..color = Colors.white);
    // Destination pin
    final dx = size.width * 0.58;
    final dy = size.height * 0.30;
    canvas.drawCircle(
        Offset(dx, dy), 16, Paint()..color = MyShopColors.success);
    canvas.drawCircle(Offset(dx, dy), 8, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ── Top bar ────────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final double w;
  final VoidCallback onBack;
  const _TopBar({required this.w, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: Row(
        children: [
          _CircleBtn(icon: Icons.arrow_back, onTap: onBack),
          const Spacer(),
          _CircleBtn(icon: Icons.my_location_rounded, onTap: () {}),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MyShopColors.surfaceWhite,
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: MyShopColors.textPrimary, size: 20),
        ),
      ),
    );
  }
}

// ── Bottom sheet ───────────────────────────────────────────────────────────────

class _BottomSheet extends StatelessWidget {
  final double w, h, bot;
  final String jobId;
  const _BottomSheet(
      {required this.w,
      required this.h,
      required this.bot,
      required this.jobId});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      padding:
          EdgeInsets.fromLTRB(w * 0.05, h * 0.020, w * 0.05, bot + h * 0.024),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: w * 0.10,
            height: 4,
            decoration: BoxDecoration(
              color: MyShopColors.surfaceGrey,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: h * 0.020),
          // ETA chip
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: w * 0.040, vertical: h * 0.014),
            decoration: BoxDecoration(
              color: MyShopColors.primaryGoldLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MyShopColors.primaryGold.withAlpha(60)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.timer_outlined,
                    color: MyShopColors.primaryGold, size: 20),
                SizedBox(width: w * 0.024),
                Text('Artisan arriving in  ',
                    style: TextStyle(
                        color: MyShopColors.textSecondary,
                        fontSize: w * 0.036)),
                Text('12 mins',
                    style: TextStyle(
                      color: MyShopColors.textPrimary,
                      fontSize: w * 0.040,
                      fontWeight: FontWeight.w800,
                    )),
              ],
            ),
          ),
          SizedBox(height: h * 0.020),
          const Divider(height: 1, color: MyShopColors.divider),
          SizedBox(height: h * 0.020),
          // Artisan row
          Row(
            children: [
              Container(
                width: w * 0.13,
                height: w * 0.13,
                decoration: const BoxDecoration(
                    color: Color(0xFF37474F), shape: BoxShape.circle),
                child: Icon(Icons.person_rounded,
                    color: Colors.white, size: w * 0.065),
              ),
              SizedBox(width: w * 0.030),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Kofi Mensah',
                        style: TextStyle(
                          color: MyShopColors.textPrimary,
                          fontSize: w * 0.040,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 3),
                    Row(children: [
                      const Icon(Icons.star_rounded,
                          color: MyShopColors.primaryGold, size: 14),
                      const SizedBox(width: 3),
                      Text('4.9  •  Master Electrician',
                          style: TextStyle(
                              color: MyShopColors.textSecondary,
                              fontSize: w * 0.032)),
                    ]),
                  ],
                ),
              ),
              // Call button
              _ContactBtn(
                icon: Icons.phone_rounded,
                color: MyShopColors.darkSlate,
                onTap: () {},
                w: w,
              ),
              SizedBox(width: w * 0.020),
              // Chat button
              _ContactBtn(
                icon: Icons.chat_bubble_outline_rounded,
                color: MyShopColors.primaryGold,
                onTap: () => context.push(AppRoutes.chat),
                w: w,
              ),
            ],
          ),
          SizedBox(height: h * 0.016),
          // Location row
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  color: MyShopColors.textSecondary, size: 16),
              SizedBox(width: w * 0.016),
              Expanded(
                child: Text('Heading to East Legon, Accra',
                    style: TextStyle(
                        color: MyShopColors.textSecondary,
                        fontSize: w * 0.034)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double w;

  const _ContactBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.w,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(w * 0.028),
          child: Icon(icon, color: color, size: w * 0.050),
        ),
      ),
    );
  }
}
