import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─── Design Tokens ─────────────────────────────────────────────────────────────
// Source: CLAUDE.md §5.2
const _kGold = Color(0xFFF5A623);
const _kDarkSlate = Color(0xFF46535D);
const _kDarkText = Color(0xFF161A1D);
const _kTextSecondary = Color(0xFF555E68);
const _kSuccess = Color(0xFF27AE60);
const _kError = Color(0xFFEB5757);

// Kumasi Central — pilot city coordinates
const _kKumasiLatLng = LatLng(6.6885, -1.6244);

// ─── Stop Model ──────────────────────────────────────────────────────────────

enum _StopType { pickup, intermediate, destination }

class _StopEntry {
  _StopEntry({required this.type, required this.address}) : id = _nextId++;
  final _StopType type;
  final String address;
  final int id;
  static int _nextId = 0;
}

// ─── Screen ──────────────────────────────────────────────────────────────────

class AddStopScreen extends ConsumerStatefulWidget {
  const AddStopScreen({super.key});

  @override
  ConsumerState<AddStopScreen> createState() => _AddStopScreenState();
}

class _AddStopScreenState extends ConsumerState<AddStopScreen> {
  // Placeholder stops — wired to PATCH /v1/rides/:id/stops in Phase 2 (EDD §4)
  final List<_StopEntry> _stops = [
    _StopEntry(type: _StopType.pickup, address: 'Ahodwo Roundabout, Kumasi'),
    _StopEntry(type: _StopType.intermediate, address: 'Kumasi City Mall (Main Entrance)'),
    _StopEntry(type: _StopType.destination, address: 'Manhyia Palace Museum'),
  ];

  void _addIntermediateStop() {
    setState(() {
      final destIndex =
          _stops.indexWhere((s) => s.type == _StopType.destination);
      _stops.insert(
        destIndex,
        _StopEntry(type: _StopType.intermediate, address: ''),
      );
    });
  }

  void _removeStop(int index) {
    if (_stops[index].type == _StopType.intermediate) {
      setState(() => _stops.removeAt(index));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kDarkText),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Your Trip',
          style: TextStyle(
            color: _kDarkText,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _kSuccess,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'In-Progress',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      ),
      body: Stack(
        children: [
          // ── Map background (non-interactive) ────────────────────────────
          IgnorePointer(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _kKumasiLatLng,
                zoom: 13.0,
              ),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
              compassEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
          // ── Content ─────────────────────────────────────────────────────
          Positioned.fill(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RouteSection(
                  stops: _stops,
                  onAddStop: _addIntermediateStop,
                  onRemoveStop: _removeStop,
                ),
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: const SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
                      child: _FareRecalculationSection(),
                    ),
                  ),
                ),
                const _Footer(),
              ],
            ),
          ),
          // ── SOS Button ──────────────────────────────────────────────────
          Positioned(
            right: 16,
            bottom: bottomPad + 158,
            child: const _SosButton(),
          ),
        ],
      ),
    );
  }
}

// ─── Route Section ────────────────────────────────────────────────────────────

class _RouteSection extends StatelessWidget {
  const _RouteSection({
    required this.stops,
    required this.onAddStop,
    required this.onRemoveStop,
  });

  final List<_StopEntry> stops;
  final VoidCallback onAddStop;
  final ValueChanged<int> onRemoveStop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'YOUR ROUTE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kDarkSlate,
                  letterSpacing: 1.4,
                ),
              ),
              Text(
                'Drag to reorder',
                style: TextStyle(fontSize: 13, color: _kTextSecondary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ..._buildRouteItems(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  List<Widget> _buildRouteItems() {
    final widgets = <Widget>[];

    for (int i = 0; i < stops.length; i++) {
      final index = i; // Capture per iteration for closure
      final stop = stops[i];
      final isLast = i == stops.length - 1;
      final isSecondToLast = i == stops.length - 2;

      widgets.add(_RouteRow(
        stop: stop,
        onRemove: stop.type == _StopType.intermediate
            ? () => onRemoveStop(index)
            : null,
      ));

      if (!isLast) {
        widgets.add(_buildConnector());

        if (isSecondToLast) {
          widgets.add(_AddStopRow(onAdd: onAddStop));
          widgets.add(_buildConnector());
        }
      }
    }

    return widgets;
  }

  Widget _buildConnector() {
    return Padding(
      padding: const EdgeInsets.only(left: 11),
      child: SizedBox(
        width: 2,
        height: 18,
        child: CustomPaint(painter: _DashedLinePainter()),
      ),
    );
  }
}

// ─── Route Row ────────────────────────────────────────────────────────────────

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.stop, this.onRemove});

  final _StopEntry stop;
  final VoidCallback? onRemove;

  String get _label => switch (stop.type) {
        _StopType.pickup => 'PICKUP',
        _StopType.intermediate => 'STOP',
        _StopType.destination => 'DESTINATION',
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _StopTypeIcon(type: stop.type),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _kTextSecondary,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        stop.address.isEmpty
                            ? 'Enter address...'
                            : stop.address,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: stop.address.isEmpty
                              ? _kTextSecondary
                              : _kDarkText,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  GestureDetector(
                    onTap: onRemove,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.delete_outline,
                          color: _kGold, size: 20),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(Icons.drag_indicator,
                    color: Colors.grey.shade400, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Stop Type Icon ───────────────────────────────────────────────────────────

class _StopTypeIcon extends StatelessWidget {
  const _StopTypeIcon({required this.type});

  final _StopType type;

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      _StopType.pickup =>
        Icon(Icons.location_on_outlined, color: _kTextSecondary, size: 24),
      _StopType.intermediate =>
        Icon(Icons.location_on_outlined, color: _kDarkSlate, size: 24),
      _StopType.destination =>
        const Icon(Icons.location_on, color: _kGold, size: 24),
    };
  }
}

// ─── Add Stop Row ─────────────────────────────────────────────────────────────

class _AddStopRow extends StatelessWidget {
  const _AddStopRow({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: CustomPaint(painter: _DashedCirclePainter()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: onAdd,
            child: CustomPaint(
              painter: _DashedRectPainter(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.add, size: 18, color: _kTextSecondary),
                    const SizedBox(width: 8),
                    Text(
                      'Add intermediate stop...',
                      style: TextStyle(
                          fontSize: 14, color: _kTextSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Fare Recalculation Section ──────────────────────────────────────────────

class _FareRecalculationSection extends StatelessWidget {
  const _FareRecalculationSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FARE RECALCULATION',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _kDarkSlate,
            letterSpacing: 1.4,
          ),
        ),
        SizedBox(height: 12),
        _PriceUpdateCard(),
        SizedBox(height: 12),
        _SurgePricingCard(),
      ],
    );
  }
}

// ─── Price Update Card ────────────────────────────────────────────────────────

class _PriceUpdateCard extends StatelessWidget {
  const _PriceUpdateCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [
          BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Gold header strip
            Container(
              color: _kGold,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Text(
                    'PRICE UPDATE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white54),
                    ),
                    child: const Text(
                      'Surge Active 1.2x',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // White body
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Original Estimate',
                          style: TextStyle(
                              fontSize: 12, color: _kTextSecondary)),
                      Text('New Upfront Fare',
                          style: TextStyle(
                              fontSize: 12, color: _kTextSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'GHS 45.00',
                        style: TextStyle(
                          fontSize: 15,
                          color: _kTextSecondary,
                          decoration: TextDecoration.lineThrough,
                          decorationColor: _kTextSecondary,
                        ),
                      ),
                      const Text(
                        'GH₵ 62.50',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _kDarkText,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: Colors.grey.shade200),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.access_time_outlined,
                          size: 16, color: _kTextSecondary),
                      const SizedBox(width: 4),
                      Text('+14 mins travel',
                          style: TextStyle(
                              fontSize: 13, color: _kTextSecondary)),
                      const Spacer(),
                      Icon(Icons.location_on_outlined,
                          size: 16, color: _kTextSecondary),
                      const SizedBox(width: 4),
                      Text('+5.2 km extra',
                          style: TextStyle(
                              fontSize: 13, color: _kTextSecondary)),
                    ],
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

// ─── Surge Pricing Card ───────────────────────────────────────────────────────

class _SurgePricingCard extends StatelessWidget {
  const _SurgePricingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _kGold,
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                const Icon(Icons.trending_up, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Surge Pricing Active',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _kDarkText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _kGold,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '1.2x',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'High demand in Kumasi. Fares are slightly higher'
                  ' to attract more drivers.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _kTextSecondary,
                    height: 1.4,
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

// ─── SOS Button ──────────────────────────────────────────────────────────────

class _SosButton extends StatelessWidget {
  const _SosButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSosDialog(context),
      child: Container(
        width: 62,
        height: 62,
        decoration: const BoxDecoration(
          color: _kError,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3)),
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security, color: Colors.white, size: 22),
            Text(
              'SOS',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSosDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emergency SOS'),
        content: const Text(
          'This will call the emergency line 191. Are you sure you '
          'want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // TODO(MSP-XX): launch phone dialer tel:191
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _kError,
              foregroundColor: Colors.white,
            ),
            child: const Text('Call 191'),
          ),
        ],
      ),
    );
  }
}

// ─── Footer ──────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Fare comparison row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Original Fare: GH₵ 45.00',
                style:
                    TextStyle(fontSize: 13, color: _kTextSecondary),
              ),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: 'Difference: ',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kDarkText,
                      ),
                    ),
                    const TextSpan(
                      text: '+GH₵ 15.00',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _kSuccess,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Confirm Changes CTA
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () {
                // TODO(MSP-XX): PATCH /v1/rides/:id/stops then pop
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kDarkSlate,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Confirm Changes',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.chevron_right, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Discard link
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Text(
              'Discard & Return to Map',
              style: TextStyle(fontSize: 14, color: _kTextSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Custom Painters ─────────────────────────────────────────────────────────

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    const dashH = 3.0;
    const dashGap = 3.0;
    double y = 0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, math.min(y + dashH, size.height)),
        paint,
      );
      y += dashH + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    const dashCount = 10;
    const sweepAngle = math.pi * 2 / dashCount * 0.55;

    for (int i = 0; i < dashCount; i++) {
      final startAngle = i * (math.pi * 2 / dashCount);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DashedRectPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    const dashLen = 6.0;
    const dashGap = 4.0;

    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5),
        const Radius.circular(8),
      ));

    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        final end = math.min(d + dashLen, metric.length);
        canvas.drawPath(metric.extractPath(d, end), paint);
        d = end + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
