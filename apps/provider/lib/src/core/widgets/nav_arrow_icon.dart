import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Generates the blue triangular chevron Google Maps uses for the
/// "you are here, heading this way" marker in navigation mode. Renders
/// once via [ui.Canvas] → [BitmapDescriptor.bytes] and is cached so
/// every GPS fix re-uses the same bitmap (Marker.rotation handles the
/// per-fix heading change, the bitmap itself is rotation-neutral).
///
/// Sizing: the rendered bitmap is twice the requested logical size
/// because Google Maps Flutter doesn't apply [imagePixelRatio] consistently
/// across platforms — at 1x the chevron renders fuzzy on high-DPR
/// devices. Render at 2x and downsample is cheaper than the alternative.
class NavArrowIcon {
  NavArrowIcon._();

  static BitmapDescriptor? _cached;

  /// Returns the cached chevron, generating it on the first call.
  /// Safe to call from anywhere on the main isolate; subsequent calls
  /// are synchronous-returning a cached value would be ideal but
  /// BitmapDescriptor build is async, so the caller awaits this once
  /// in initState and stores the result.
  static Future<BitmapDescriptor> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final bytes = await _renderBytes();
    final descriptor = BitmapDescriptor.bytes(bytes);
    _cached = descriptor;
    return descriptor;
  }

  static Future<Uint8List> _renderBytes() async {
    const logicalSize = 56.0;
    const scale = 2.0;
    const size = logicalSize * scale;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);

    // Outer white halo so the chevron pops on any map background.
    final haloPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final outerArrow = _chevronPath(center: center, size: size * 0.92);
    canvas.drawPath(outerArrow, haloPaint);

    // Blue chevron — same hue as Google Maps' navigation arrow.
    final arrowPaint = Paint()
      ..color = const Color(0xFF1A73E8)
      ..style = PaintingStyle.fill;
    final innerArrow = _chevronPath(center: center, size: size * 0.78);
    canvas.drawPath(innerArrow, arrowPaint);

    // Soft drop shadow under the chevron for depth on flat road tiles.
    final shadow = Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(center.translate(0, size * 0.05), size * 0.18, shadow);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Triangular chevron pointing UP. The Marker's `rotation` property
  /// handles heading — we just draw a clean north-pointing arrow once.
  /// Slight notch at the base mirrors Google Maps' shape so it doesn't
  /// read as a generic triangle.
  static Path _chevronPath({required Offset center, required double size}) {
    final half = size / 2;
    final path = Path();
    // Tip at top
    path.moveTo(center.dx, center.dy - half);
    // Right shoulder
    path.lineTo(center.dx + half * 0.7, center.dy + half * 0.85);
    // Notch
    path.lineTo(center.dx, center.dy + half * 0.45);
    // Left shoulder
    path.lineTo(center.dx - half * 0.7, center.dy + half * 0.85);
    path.close();
    return path;
  }
}
