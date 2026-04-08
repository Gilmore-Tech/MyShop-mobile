import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// A clean weekly bar chart with Y-axis labels and gridlines.
///
/// Used inside the Earnings Dashboard "Weekly Performance" card.
/// Matches the Figma design: dark slate bars, dotted gridlines,
/// numeric Y-axis on the left, day labels Mon–Sun on the bottom.
class WeeklyPerformanceChart extends StatelessWidget {
  const WeeklyPerformanceChart({
    super.key,
    required this.values,
    required this.maxValue,
  });

  /// Seven values, one per day Mon–Sun.
  final List<double> values;

  /// Highest gridline value (e.g. 460).
  final double maxValue;

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    assert(values.length == 7, 'Provide 7 values, one per day.');

    // Y-axis label values (4 lines + 0)
    final step = maxValue / 4;
    final yLabels = List.generate(5, (i) => (maxValue - step * i).round())
        .map((v) => v.toString())
        .toList();

    return SizedBox(
      height: 200,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Y-axis labels ──
          SizedBox(
            width: 32,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final label in yLabels) ...[
                  Text(
                    label,
                    style: MyShopTypography.caption.copyWith(
                      fontSize: 11,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
                // bottom spacer for x-axis labels
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
                  child: Stack(
                    children: [
                      // Gridlines
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GridlinePainter(),
                        ),
                      ),
                      // Bars
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < values.length; i++) ...[
                              Expanded(
                                child: _Bar(
                                  fraction: (values[i] / maxValue).clamp(0, 1),
                                ),
                              ),
                              if (i < values.length - 1) const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // X-axis labels
                Row(
                  children: [
                    for (var i = 0; i < _days.length; i++) ...[
                      Expanded(
                        child: Center(
                          child: Text(
                            _days[i],
                            style: MyShopTypography.caption.copyWith(
                              fontSize: 11,
                              color: MyShopColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      if (i < _days.length - 1) const SizedBox(width: 8),
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
}

class _Bar extends StatelessWidget {
  const _Bar({required this.fraction});
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: constraints.maxWidth,
            height: constraints.maxHeight * fraction,
            decoration: BoxDecoration(
              color: MyShopColors.darkSlate,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(4),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GridlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MyShopColors.divider
      ..strokeWidth = 0.5;

    // Draw 5 horizontal gridlines (top, 3 middle, bottom)
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
  bool shouldRepaint(covariant _GridlinePainter oldDelegate) => false;
}
