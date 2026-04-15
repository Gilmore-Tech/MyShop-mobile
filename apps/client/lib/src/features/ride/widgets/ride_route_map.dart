import 'package:flutter/material.dart';

import '../providers/ride_provider.dart' show RideTrackingPhase;

// Design tokens
const _gold = Color(0xFFF5A623);
const _mapBg = Color(0xFFEDEDE6);      // Warm off-white map background
const _mapGrid = Color(0xFFE2E2DB);    // Subtle grid lines
const _routeColor = Color(0xFF1C1C1E); // Dark route line
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _success = Color(0xFF27AE60);

class RideRouteMap extends StatelessWidget {
  final String destination;
  final int etaMinutes;
  final RideTrackingPhase phase;

  const RideRouteMap({
    super.key,
    required this.destination,
    required this.etaMinutes,
    this.phase = RideTrackingPhase.enRoute,
  });

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        Positioned.fill(child: _MapCanvas()),
        Positioned(
          top: statusBarHeight + 10,
          left: 0,
          right: 0,
          child: Center(child: _topPill()),
        ),
        Positioned(
          top: statusBarHeight + 62,
          left: 16,
          right: 16,
          child: _DestinationOverlay(destination: destination),
        ),
      ],
    );
  }

  Widget _topPill() {
    switch (phase) {
      case RideTrackingPhase.enRoute:
        return _EtaPill(etaMinutes: etaMinutes);
      case RideTrackingPhase.arrived:
        return const _ArrivedPill();
      case RideTrackingPhase.inProgress:
        return _InProgressPill(minutes: etaMinutes);
    }
  }
}

// ── Map canvas with custom-painted route ──────────────────────────────────────

class _MapCanvas extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RoutePainter(),
      child: Container(color: _mapBg),
    );
  }
}

class _RoutePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    _drawMapGrid(canvas, size);
    _drawRoute(canvas, size);
    _drawDestinationDot(canvas, size);
    _drawDriverMarker(canvas, size);
  }

  void _drawMapGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _mapGrid
      ..strokeWidth = 1;

    // Horizontal grid lines (simulating map roads)
    for (var i = 1; i < 6; i++) {
      final y = size.height * i / 6;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    // Vertical grid lines
    for (var i = 1; i < 4; i++) {
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  void _drawRoute(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _routeColor
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final startX = size.width * 0.38;
    final startY = size.height * 0.22;
    final endX = size.width * 0.42;
    final endY = size.height * 0.78;

    final path = Path()
      ..moveTo(startX, startY)
      ..cubicTo(
        startX - 18, startY + (endY - startY) * 0.35,
        endX + 22, startY + (endY - startY) * 0.62,
        endX, endY,
      );

    canvas.drawPath(path, paint);
  }

  void _drawDestinationDot(Canvas canvas, Size size) {
    final cx = size.width * 0.38;
    final cy = size.height * 0.22;

    // White halo
    canvas.drawCircle(
      Offset(cx, cy),
      9,
      Paint()..color = Colors.white,
    );
    // Gold fill
    canvas.drawCircle(
      Offset(cx, cy),
      6,
      Paint()..color = _gold,
    );
  }

  void _drawDriverMarker(Canvas canvas, Size size) {
    final cx = size.width * 0.42;
    final cy = size.height * 0.78;

    // Shadow
    canvas.drawCircle(
      Offset(cx, cy + 2),
      14,
      Paint()..color = Colors.black.withValues(alpha: 0.12),
    );
    // White circle background
    canvas.drawCircle(
      Offset(cx, cy),
      13,
      Paint()..color = Colors.white,
    );
    // Dark border ring
    canvas.drawCircle(
      Offset(cx, cy),
      13,
      Paint()
        ..color = _routeColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    // Car icon drawn via TextPainter (emoji-like)
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🚗',
        style: TextStyle(fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(cx - textPainter.width / 2, cy - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EtaPill extends StatelessWidget {
  final int etaMinutes;
  const _EtaPill({required this.etaMinutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.timer_outlined, size: 14, color: _textPrimary),
          const SizedBox(width: 6),
          Text(
            'ARRIVING IN $etaMinutes MINS',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card shell ───────────────────────────────────────────────────────────────

BoxDecoration _cardDecoration() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 12,
          offset: const Offset(0, 3),
        ),
      ],
    );

// ── Destination (HEADING TO) card ─────────────────────────────────────────────

class _DestinationOverlay extends StatelessWidget {
  final String destination;
  const _DestinationOverlay({required this.destination});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      decoration: _cardDecoration(),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _RouteRail(),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'HEADING TO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    destination,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

// ── Arrived pill + waiting card ──────────────────────────────────────────────

class _ArrivedPill extends StatelessWidget {
  const _ArrivedPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: _success,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _success.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
          SizedBox(width: 6),
          Text(
            'YOUR DRIVER IS HERE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _InProgressPill extends StatelessWidget {
  final int minutes;
  const _InProgressPill({required this.minutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF46535D),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.navigation_rounded, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            'IN TRANSIT · $minutes MIN',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}


/// Gold rail: filled dot → dashed vertical line → outlined circle.
class _RouteRail extends StatelessWidget {
  const _RouteRail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Top — solid gold dot (origin marker)
          Container(
            width: 12,
            height: 12,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _gold,
            ),
          ),
          // Middle — dashed connector
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 3),
              child: CustomPaint(painter: _DashedLinePainter()),
            ),
          ),
          // Bottom — hollow gold ring (destination marker)
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(color: _gold, width: 2),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _gold
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const dash = 2.0;
    const gap = 3.0;
    final cx = size.width / 2;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + dash), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
