import 'package:flutter/material.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _mapBg = Color(0xFFEDEDE6);      // Warm off-white map background
const _mapGrid = Color(0xFFE2E2DB);    // Subtle grid lines
const _routeColor = Color(0xFF1C1C1E); // Dark route line
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);

class RideRouteMap extends StatelessWidget {
  final String destination;
  final int etaMinutes;
  final VoidCallback? onBack;

  const RideRouteMap({
    super.key,
    required this.destination,
    required this.etaMinutes,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    return Stack(
      children: [
        // Map background + route
        Positioned.fill(child: _MapCanvas()),
        // Back button — flush against the status bar
        Positioned(
          top: statusBarHeight + 6,
          left: 12,
          child: _BackButton(onTap: onBack),
        ),
        // ETA pill — centred, slightly lower so it clears the back button
        Positioned(
          top: statusBarHeight + 10,
          left: 0,
          right: 0,
          child: Center(child: _EtaPill(etaMinutes: etaMinutes)),
        ),
        // Destination label overlay (top-left of route)
        _DestinationOverlay(destination: destination),
      ],
    );
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

class _BackButton extends StatelessWidget {
  final VoidCallback? onTap;
  const _BackButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).pop(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.arrow_back_rounded,
            size: 20, color: _textPrimary),
      ),
    );
  }
}

class _EtaPill extends StatelessWidget {
  final int etaMinutes;
  const _EtaPill({required this.etaMinutes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
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
      child: Text(
        'ARRIVING IN $etaMinutes MINS',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _textPrimary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

// ── Destination label overlay ─────────────────────────────────────────────────

class _DestinationOverlay extends StatelessWidget {
  final String destination;
  const _DestinationOverlay({required this.destination});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 64,
      left: 20,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'HEADING TO',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _textSecondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_rounded, color: _gold, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  destination,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
