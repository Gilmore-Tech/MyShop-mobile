import 'package:flutter/material.dart';

/// Compact price disclosure; the fare already includes this multiplier.
class SurgePriceIndicator extends StatelessWidget {
  const SurgePriceIndicator({super.key, required this.multiplier});
  final double multiplier;

  @override
  Widget build(BuildContext context) {
    final rate = multiplier.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
    return Tooltip(
      message: 'Higher demand · $rate× pricing',
      child: Semantics(
        label: 'Surge pricing, $rate times the standard fare',
        child: const Icon(Icons.trending_up_rounded,
            size: 15, color: Color(0xFFCC6B20)),
      ),
    );
  }
}
