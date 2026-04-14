import 'package:flutter/material.dart';
import '../providers/edit_trip_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _goldLight = Color(0xFFFFF8EC);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _textHint = Color(0xFFBDBDBD);
const _border = Color(0xFFE0E0E0);
const _lineColor = Color(0xFFDDDDDD);
const _error = Color(0xFFEB5757);
const _darkSlate = Color(0xFF46535D);

/// Renders the ordered route stop list with a connecting vertical line,
/// type indicators, drag handles, and a "+ Add intermediate stop" row.
class RouteStopList extends StatelessWidget {
  final List<TripStop> stops;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(String id) onRemove;
  final VoidCallback onAddStop;

  const RouteStopList({
    super.key,
    required this.stops,
    required this.onReorder,
    required this.onRemove,
    required this.onAddStop,
  });

  @override
  Widget build(BuildContext context) {
    // Separate pickup + intermediates from destination so we can insert
    // the "Add stop" row before destination.
    final nonDestination =
        stops.where((s) => s.type != StopType.destination).toList();
    final destination =
        stops.where((s) => s.type == StopType.destination).firstOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reorderable pickup + intermediate stops
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          onReorder: onReorder,
          proxyDecorator: (child, index, animation) => Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(10),
            child: child,
          ),
          children: [
            for (final stop in nonDestination)
              _StopRow(
                key: ValueKey(stop.id),
                stop: stop,
                isFirst: nonDestination.first == stop,
                isLast: false,
                showLine: true,
                onRemove: stop.type == StopType.intermediate
                    ? () => onRemove(stop.id)
                    : null,
              ),
          ],
        ),
        // Add intermediate stop row
        _AddStopRow(onTap: onAddStop),
        // Destination stop (not reorderable)
        if (destination != null)
          _StopRow(
            key: ValueKey(destination.id),
            stop: destination,
            isFirst: false,
            isLast: true,
            showLine: false,
            onRemove: null,
          ),
      ],
    );
  }
}

// ── Individual stop row ───────────────────────────────────────────────────────

class _StopRow extends StatelessWidget {
  final TripStop stop;
  final bool isFirst;
  final bool isLast;
  final bool showLine;
  final VoidCallback? onRemove;

  const _StopRow({
    super.key,
    required this.stop,
    required this.isFirst,
    required this.isLast,
    required this.showLine,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left: connector + indicator
            SizedBox(
              width: 36,
              child: _StopIndicatorColumn(
                type: stop.type,
                showLineAbove: !isFirst,
                showLineBelow: showLine,
              ),
            ),
            // Right: content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _StopContent(stop: stop, onRemove: onRemove),
              ),
            ),
            // Drag handle (hidden for pickup/destination in a real impl)
            if (stop.type != StopType.destination)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: _textHint,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StopIndicatorColumn extends StatelessWidget {
  final StopType type;
  final bool showLineAbove;
  final bool showLineBelow;

  const _StopIndicatorColumn({
    required this.type,
    required this.showLineAbove,
    required this.showLineBelow,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Vertical connecting line
        Positioned(
          left: 17,
          top: showLineAbove ? 0 : null,
          bottom: showLineBelow ? 0 : null,
          height: showLineAbove || showLineBelow ? null : 0,
          child: Container(width: 2, color: _lineColor),
        ),
        // Stop indicator dot
        _StopDot(type: type),
      ],
    );
  }
}

class _StopDot extends StatelessWidget {
  final StopType type;
  const _StopDot({required this.type});

  @override
  Widget build(BuildContext context) {
    return switch (type) {
      StopType.pickup => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: _textSecondary, width: 2),
          ),
        ),
      StopType.intermediate => Container(
          width: 14,
          height: 14,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _darkSlate,
          ),
        ),
      StopType.destination => Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: _textPrimary,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
    };
  }
}

class _StopContent extends StatelessWidget {
  final TripStop stop;
  final VoidCallback? onRemove;

  const _StopContent({required this.stop, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          stop.typeLabel,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: _textSecondary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                stop.address,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _textPrimary,
                ),
              ),
            ),
            if (onRemove != null)
              GestureDetector(
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 18, color: _error),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Add intermediate stop row ─────────────────────────────────────────────────

class _AddStopRow extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStopRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.white,
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 17,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 2, color: _lineColor),
                  ),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _goldLight,
                      border: Border.all(
                          color: _gold.withValues(alpha: 0.5), width: 1.5),
                    ),
                    child: const Icon(Icons.add, size: 12, color: _gold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Add intermediate stop...',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _gold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
