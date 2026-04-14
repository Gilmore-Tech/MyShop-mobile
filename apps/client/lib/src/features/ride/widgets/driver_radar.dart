import 'dart:math' as math;
import 'package:flutter/material.dart';

// Design tokens
const _gold       = Color(0xFFF5A623);
const _radarFill  = Color(0xFFF5E8D0); // warm sand/cream
const _pinColor   = Color(0xFF161A1D); // dark navy pin

/// Radar widget — full-size static circle with an outward-expanding pulse ring.
/// The main disc stays at full size; the ring expands from the edge and fades.
class DriverRadar extends StatefulWidget {
  final bool driversFound;
  final int  driversAvailable;

  const DriverRadar({
    super.key,
    this.driversFound    = false,
    this.driversAvailable = 0,
  });

  @override
  State<DriverRadar> createState() => _DriverRadarState();
}

class _DriverRadarState extends State<DriverRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _expand;
  late final Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Ring expands from 1.0 (circle edge) to 1.18 (slightly outside)
    _expand = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    // Ring fades from semi-opaque to transparent
    _fade = Tween<double>(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
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
      builder: (_, __) => _RadarBody(
        expandScale:  _expand.value,
        ringOpacity:  _fade.value,
        driversFound: widget.driversFound,
      ),
    );
  }
}

class _RadarBody extends StatelessWidget {
  final double expandScale;
  final double ringOpacity;
  final bool   driversFound;

  const _RadarBody({
    required this.expandScale,
    required this.ringOpacity,
    required this.driversFound,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final size   = math.min(constraints.maxWidth, constraints.maxHeight);
        final radius = size / 2;

        return SizedBox(
          width:  size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // ── Expanding pulse ring ───────────────────────────────────────
              Transform.scale(
                scale: expandScale,
                child: Container(
                  width:  size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _gold.withAlpha((ringOpacity * 255).round()),
                      width: 3,
                    ),
                  ),
                ),
              ),

              // ── Main disc ─────────────────────────────────────────────────
              Container(
                width:  size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _radarFill,
                  border: Border.all(color: _gold, width: 2.5),
                ),
              ),

              // ── Pin marker ────────────────────────────────────────────────
              _PinMarker(size: size),

              // ── Car icons when driver found ────────────────────────────────
              if (driversFound) ..._carIcons(radius * 0.65),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _carIcons(double orbit) {
    const angles = [30.0, 140.0, 220.0];
    return angles.map((deg) {
      final rad = deg * (math.pi / 180);
      return Transform.translate(
        offset: Offset(math.cos(rad) * orbit, math.sin(rad) * orbit),
        child: _CarIcon(),
      );
    }).toList();
  }
}

// ── Pin ────────────────────────────────────────────────────────────────────────

class _PinMarker extends StatelessWidget {
  final double size;
  const _PinMarker({required this.size});

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.14;
    return Container(
      width:  iconSize * 1.8,
      height: iconSize * 1.8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withAlpha(24),
            blurRadius: 10,
            offset:     const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        Icons.location_on_rounded,
        color: _pinColor,
        size:  iconSize,
      ),
    );
  }
}

// ── Car icon ───────────────────────────────────────────────────────────────────

class _CarIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width:  36,
      height: 36,
      decoration: BoxDecoration(
        color:  Colors.white,
        shape:  BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withAlpha(20),
            blurRadius: 4,
            offset:     const Offset(0, 1),
          ),
        ],
      ),
      child: const Icon(
        Icons.directions_car_rounded,
        size:  18,
        color: Color(0xFF46535D),
      ),
    );
  }
}
