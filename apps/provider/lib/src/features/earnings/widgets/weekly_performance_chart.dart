import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// A clean bar chart with Y-axis labels and gridlines.
///
/// Renders the gap-filled `series[]` from the earnings summary or report
/// endpoint as a vertical bar per bucket. Y-axis labels are derived from
/// [maxValue] and rounded to a clean tick.
class WeeklyPerformanceChart extends StatelessWidget {
  const WeeklyPerformanceChart({
    super.key,
    required this.values,
    required this.maxValue,
    required this.xLabels,
  });

  /// One value per bar (left → right). Length must equal [xLabels.length].
  final List<double> values;

  /// Highest gridline value (e.g. 460).
  final double maxValue;

  /// X-axis labels rendered under each bar (Mon..Sun, 1..30, week numbers).
  final List<String> xLabels;

  @override
  Widget build(BuildContext context) {
    assert(values.length == xLabels.length,
        'values and xLabels must be the same length.');

    final step = maxValue / 4;
    final yLabels = List.generate(5, (i) => (maxValue - step * i).round())
        .map(_compactLabel)
        .toList();

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
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _GridlinePainter(),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < values.length; i++) ...[
                              Expanded(
                                child: _Bar(
                                  fraction: maxValue == 0
                                      ? 0
                                      : (values[i] / maxValue).clamp(0, 1),
                                ),
                              ),
                              if (i < values.length - 1)
                                const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (var i = 0; i < xLabels.length; i++) ...[
                      Expanded(
                        child: Center(
                          child: Text(
                            xLabels[i],
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: MyShopTypography.caption.copyWith(
                              fontSize: 11,
                              color: MyShopColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      if (i < xLabels.length - 1) const SizedBox(width: 8),
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

  /// Compacts axis labels so a 12,000 value renders as "12k" instead of
  /// blowing past the 36px Y-axis lane.
  static String _compactLabel(int v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) {
      return '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k';
    }
    return v.toString();
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

    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      _drawDashedLine(canvas, Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
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
