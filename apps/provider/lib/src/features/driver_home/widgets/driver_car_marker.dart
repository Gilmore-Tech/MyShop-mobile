import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Generates the [BitmapDescriptor] we use to represent the driver on the map
/// while they are online. Drawn programmatically (rather than shipping a PNG)
/// so the marker stays crisp at any device pixel ratio.
///
/// The marker is a stylised top-down white sedan (à la Uber / Bolt): rounded
/// white body, dark windshield and rear window, tiny head- and tail-lights,
/// and a soft drop shadow. The car's nose points toward the top of the
/// bitmap, so when Google Maps rotates the marker by `position.heading` the
/// nose faces the direction of travel.
///
/// The output canvas is square so rotation always happens around the car's
/// visual centre.
class DriverCarMarker {
  const DriverCarMarker._();

  static Future<BitmapDescriptor> create({
    double devicePixelRatio = 3.0,
  }) async {
    // Logical size of the square bitmap. The car itself occupies the middle
    // column — extra horizontal space is just margin for the drop shadow.
    const logicalSize = 72.0;
    final size = logicalSize * devicePixelRatio;

    // Car body bounds inside the bitmap (nose at top).
    const carWidthLogical = 36.0;
    const carHeightLogical = 64.0;
    final carWidth = carWidthLogical * devicePixelRatio;
    final carHeight = carHeightLogical * devicePixelRatio;
    final carLeft = (size - carWidth) / 2;
    final carTop = (size - carHeight) / 2;
    final carRight = carLeft + carWidth;
    final carBottom = carTop + carHeight;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // ── Drop shadow ──
    final shadowRect = RRect.fromLTRBR(
      carLeft,
      carTop + 2 * devicePixelRatio,
      carRight,
      carBottom + 2 * devicePixelRatio,
      Radius.circular(14 * devicePixelRatio),
    );
    canvas.drawRRect(
      shadowRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          5 * devicePixelRatio,
        ),
    );

    // ── Body (white, rounded rectangle) ──
    final bodyRect = RRect.fromLTRBR(
      carLeft,
      carTop,
      carRight,
      carBottom,
      Radius.circular(14 * devicePixelRatio),
    );
    canvas.drawRRect(bodyRect, Paint()..color = Colors.white);

    // Subtle 1px outline so the white body doesn't fade into light map tiles.
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = const Color(0xFFCED4DA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * devicePixelRatio,
    );

    // ── Windshield (upper dark band, slightly trapezoidal) ──
    final glassColor = const Color(0xFF1F2A36).withValues(alpha: 0.85);
    final windshieldPath = Path()
      ..moveTo(carLeft + 8 * devicePixelRatio, carTop + 10 * devicePixelRatio)
      ..lineTo(carRight - 8 * devicePixelRatio, carTop + 10 * devicePixelRatio)
      ..lineTo(carRight - 5 * devicePixelRatio, carTop + 24 * devicePixelRatio)
      ..lineTo(carLeft + 5 * devicePixelRatio, carTop + 24 * devicePixelRatio)
      ..close();
    canvas.drawPath(windshieldPath, Paint()..color = glassColor);

    // ── Rear window (lower dark band, mirrored trapezoid) ──
    final rearWindowPath = Path()
      ..moveTo(
          carLeft + 5 * devicePixelRatio, carBottom - 22 * devicePixelRatio)
      ..lineTo(
          carRight - 5 * devicePixelRatio, carBottom - 22 * devicePixelRatio)
      ..lineTo(
          carRight - 8 * devicePixelRatio, carBottom - 10 * devicePixelRatio)
      ..lineTo(
          carLeft + 8 * devicePixelRatio, carBottom - 10 * devicePixelRatio)
      ..close();
    canvas.drawPath(rearWindowPath, Paint()..color = glassColor);

    // ── Roof divider line between windshield and rear window ──
    canvas.drawLine(
      Offset(carLeft + 4 * devicePixelRatio, carTop + carHeight / 2),
      Offset(carRight - 4 * devicePixelRatio, carTop + carHeight / 2),
      Paint()
        ..color = const Color(0xFFCED4DA)
        ..strokeWidth = 0.8 * devicePixelRatio,
    );

    // ── Headlights (two warm dots at the nose) ──
    final headlightPaint = Paint()..color = const Color(0xFFFFE9A8);
    final headlightRadius = 1.8 * devicePixelRatio;
    canvas.drawCircle(
      Offset(carLeft + 7 * devicePixelRatio, carTop + 5 * devicePixelRatio),
      headlightRadius,
      headlightPaint,
    );
    canvas.drawCircle(
      Offset(carRight - 7 * devicePixelRatio, carTop + 5 * devicePixelRatio),
      headlightRadius,
      headlightPaint,
    );

    // ── Tail-lights (two red dots at the rear) ──
    final taillightPaint = Paint()..color = const Color(0xFFE53935);
    canvas.drawCircle(
      Offset(carLeft + 7 * devicePixelRatio, carBottom - 5 * devicePixelRatio),
      headlightRadius,
      taillightPaint,
    );
    canvas.drawCircle(
      Offset(carRight - 7 * devicePixelRatio, carBottom - 5 * devicePixelRatio),
      headlightRadius,
      taillightPaint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(byteData!.buffer.asUint8List());
  }
}
