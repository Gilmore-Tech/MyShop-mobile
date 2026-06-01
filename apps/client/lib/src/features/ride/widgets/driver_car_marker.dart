import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Live-driver marker used on the rider's tracking map.
///
/// Identical to the provider app's `DriverCarMarker` (see
/// `apps/provider/.../widgets/driver_car_marker.dart`) — kept in sync by
/// hand for v1.0. v1.1 should hoist this into `packages/shared_ui/` so
/// both apps consume one source of truth.
///
/// Drawn programmatically (rather than shipping a PNG asset) so it stays
/// crisp at any device pixel ratio. Square canvas so the marker rotates
/// cleanly around its visual centre when Google Maps applies the
/// driver's heading.
class DriverCarMarker {
  const DriverCarMarker._();

  static Future<BitmapDescriptor> create({
    double devicePixelRatio = 3.0,
    double scale = 0.7,
  }) async {
    const logicalSize = 72.0;
    final size = logicalSize * devicePixelRatio;

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

    // Drop shadow.
    canvas.drawRRect(
      RRect.fromLTRBR(
        carLeft,
        carTop + 2 * devicePixelRatio,
        carRight,
        carBottom + 2 * devicePixelRatio,
        Radius.circular(14 * devicePixelRatio),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, 5 * devicePixelRatio),
    );

    // White body.
    final bodyRect = RRect.fromLTRBR(
      carLeft,
      carTop,
      carRight,
      carBottom,
      Radius.circular(14 * devicePixelRatio),
    );
    canvas.drawRRect(bodyRect, Paint()..color = Colors.white);
    canvas.drawRRect(
      bodyRect,
      Paint()
        ..color = const Color(0xFFCED4DA)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 * devicePixelRatio,
    );

    // Windshield (front).
    final glassColor = const Color(0xFF1F2A36).withValues(alpha: 0.85);
    final windshieldPath = Path()
      ..moveTo(carLeft + 8 * devicePixelRatio, carTop + 10 * devicePixelRatio)
      ..lineTo(carRight - 8 * devicePixelRatio, carTop + 10 * devicePixelRatio)
      ..lineTo(carRight - 5 * devicePixelRatio, carTop + 24 * devicePixelRatio)
      ..lineTo(carLeft + 5 * devicePixelRatio, carTop + 24 * devicePixelRatio)
      ..close();
    canvas.drawPath(windshieldPath, Paint()..color = glassColor);

    // Rear window.
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

    // Roof divider.
    canvas.drawLine(
      Offset(carLeft + 4 * devicePixelRatio, carTop + carHeight / 2),
      Offset(carRight - 4 * devicePixelRatio, carTop + carHeight / 2),
      Paint()
        ..color = const Color(0xFFCED4DA)
        ..strokeWidth = 0.8 * devicePixelRatio,
    );

    // Headlights.
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

    // Tail-lights.
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
    return BitmapDescriptor.bytes(
      byteData!.buffer.asUint8List(),
      imagePixelRatio: devicePixelRatio / scale,
    );
  }
}
