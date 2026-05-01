import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Single-series line chart used by the report breakdown.
///
/// Mirrors the bar chart's layout (Y-axis labels left, dashed gridlines,
/// X-axis labels bottom) so the two charts read as a coherent pair.
/// Renders a smooth polyline through bucket midpoints with a soft fill
/// underneath, tappable dots at each point, and a tooltip on press.
class EarningsLineChart extends StatefulWidget {
  const EarningsLineChart({
    super.key,
    required this.values,
    required this.maxValue,
    required this.xLabels,
    required this.tooltipBuilder,
  });

  /// One value per point (left → right). Length must equal [xLabels.length].
  final List<double> values;

  /// Highest gridline value. Pass a slightly-padded max (e.g. `max * 1.15`)
  /// so the topmost point doesn't pin to the chart's top edge.
  final double maxValue;

  /// X-axis labels rendered under each point. Same length as [values].
  final List<String> xLabels;

  /// Builds the tooltip body for the dot at `index`. Called only while a
  /// point is held; should be cheap.
  final String Function(int index) tooltipBuilder;

  @override
  State<EarningsLineChart> createState() => _EarningsLineChartState();
}

class _EarningsLineChartState extends State<EarningsLineChart> {
  int? _activeIndex;

  @override
  Widget build(BuildContext context) {
    assert(widget.values.length == widget.xLabels.length,
        'values and xLabels must be the same length.');

    final yLabels = _yLabels(widget.maxValue);

    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Y-axis labels ──
          SizedBox(
            width: 36,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final label in yLabels)
                  Text(
                    label,
                    style: MyShopTypography.caption.copyWith(
                      fontSize: 11,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 18),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // ── Plot area ──
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) =>
                        setState(() => _activeIndex = _hitIndex(d.localPosition)),
                    onPanUpdate: (d) =>
                        setState(() => _activeIndex = _hitIndex(d.localPosition)),
                    onPanEnd: (_) => setState(() => _activeIndex = null),
                    onTapUp: (_) => setState(() => _activeIndex = null),
                    onTapCancel: () => setState(() => _activeIndex = null),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _LineChartPainter(
                                  values: widget.values,
                                  maxValue: widget.maxValue,
                                  activeIndex: _activeIndex,
                                ),
                              ),
                            ),
                            if (_activeIndex != null)
                              _Tooltip(
                                anchor: _pointPosition(
                                  index: _activeIndex!,
                                  size: constraints.biggest,
                                ),
                                text: widget.tooltipBuilder(_activeIndex!),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < widget.xLabels.length; i++) ...[
                      Expanded(
                        child: Center(
                          child: Text(
                            widget.xLabels[i],
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: MyShopTypography.caption.copyWith(
                              fontSize: 11,
                              color: MyShopColors.textSecondary,
                              fontWeight: i == _activeIndex
                                  ? FontWeight.w900
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                      if (i < widget.xLabels.length - 1)
                        const SizedBox(width: 8),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int? _hitIndex(Offset local) {
    if (widget.values.isEmpty) return null;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;
    final width = _plotWidth();
    if (width <= 0) return null;
    final dx = local.dx.clamp(0.0, width);
    final stepX = width / (widget.values.length - 1).clamp(1, 9999);
    final idx = (dx / stepX).round();
    return idx.clamp(0, widget.values.length - 1);
  }

  double _plotWidth() {
    final box = context.findRenderObject();
    if (box is RenderBox) {
      // The GestureDetector wraps the plot stack which fills the lane
      // between the Y-axis (36 + 8 px) and the right edge.
      return box.size.width - 36 - 8;
    }
    return 0;
  }

  Offset _pointPosition({required int index, required Size size}) {
    final stepX = widget.values.length == 1
        ? size.width / 2
        : size.width / (widget.values.length - 1);
    final x = widget.values.length == 1 ? size.width / 2 : index * stepX;
    final fraction = widget.maxValue == 0
        ? 0.0
        : (widget.values[index] / widget.maxValue).clamp(0.0, 1.0);
    final y = size.height - size.height * fraction;
    return Offset(x, y);
  }

  /// 5 ticks (0..max) compacted to "12k", "1.2M" etc. so the tightest values
  /// don't blow past the 36px Y-axis lane.
  static List<String> _yLabels(double maxValue) {
    final step = maxValue / 4;
    return List.generate(5, (i) {
      final v = (maxValue - step * i).round();
      if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
      if (v >= 1000) return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
      return v.toString();
    });
  }
}

class _Tooltip extends StatelessWidget {
  const _Tooltip({required this.anchor, required this.text});

  final Offset anchor;
  final String text;

  @override
  Widget build(BuildContext context) {
    // Position the tooltip just above the hit point. Clamp so it doesn't
    // overflow the chart bounds for the leftmost/rightmost points.
    return Positioned(
      left: (anchor.dx - 60).clamp(0.0, double.infinity),
      top: (anchor.dy - 44).clamp(0.0, double.infinity),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: MyShopColors.darkSlate,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: 'Raleway',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({
    required this.values,
    required this.maxValue,
    required this.activeIndex,
  });

  final List<double> values;
  final double maxValue;
  final int? activeIndex;

  @override
  void paint(Canvas canvas, Size size) {
    _drawGridlines(canvas, size);
    if (values.isEmpty || maxValue == 0) return;

    final points = _points(size);

    // Soft area fill under the line — gives the line some weight without
    // dominating the chart background.
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    final fill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          MyShopColors.primaryGold.withValues(alpha: 0.25),
          MyShopColors.primaryGold.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fill);

    // Polyline stroke.
    final stroke = Paint()
      ..color = MyShopColors.primaryGold
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }
    canvas.drawPath(linePath, stroke);

    // Dots — solid gold for inactive points, dark slate ring for the
    // currently-pressed point so the tooltip's anchor is unambiguous.
    final dotFill = Paint()..color = MyShopColors.primaryGold;
    final dotRing = Paint()
      ..color = MyShopColors.darkSlate
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (i == activeIndex) {
        canvas.drawCircle(p, 6, dotFill);
        canvas.drawCircle(p, 6, dotRing);
      } else {
        canvas.drawCircle(p, 3.5, dotFill);
      }
    }
  }

  List<Offset> _points(Size size) {
    final stepX = values.length == 1
        ? size.width / 2
        : size.width / (values.length - 1);
    return List.generate(values.length, (i) {
      final x = values.length == 1 ? size.width / 2 : i * stepX;
      final fraction = (values[i] / maxValue).clamp(0.0, 1.0);
      final y = size.height - size.height * fraction;
      return Offset(x, y);
    });
  }

  void _drawGridlines(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MyShopColors.divider
      ..strokeWidth = 0.5;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawDashedLine(
      Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashWidth = 4.0;
    const dashSpace = 4.0;
    final totalDistance = (end - start).distance;
    final dashCount = (totalDistance / (dashWidth + dashSpace)).floor();
    final dx = (end.dx - start.dx) / totalDistance;
    final dy = (end.dy - start.dy) / totalDistance;
    var currentX = start.dx;
    var currentY = start.dy;
    for (var i = 0; i < dashCount; i++) {
      final nextX = currentX + dx * dashWidth;
      final nextY = currentY + dy * dashWidth;
      canvas.drawLine(Offset(currentX, currentY), Offset(nextX, nextY), paint);
      currentX = nextX + dx * dashSpace;
      currentY = nextY + dy * dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter old) =>
      old.values != values ||
      old.maxValue != maxValue ||
      old.activeIndex != activeIndex;
}
