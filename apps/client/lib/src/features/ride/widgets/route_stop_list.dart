import 'package:flutter/material.dart';
import '../providers/edit_trip_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _goldLight = Color(0xFFFFF8EC);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _textHint = Color(0xFFBDBDBD);
const _border = Color(0xFFE0E0E0);
const _error = Color(0xFFEB5757);
const _darkSlate = Color(0xFF46535D);

/// Stop list rendered as standalone input-style cards.
/// Each card mirrors the pickup/destination inputs elsewhere in the app —
/// tappable, with a dot indicator on the left and a drag handle on the
/// right. Pickup stays pinned at the top; destination stays at the bottom.
/// Intermediate stops are reorderable and removable.
class RouteStopList extends StatelessWidget {
  final List<TripStop> stops;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(String id) onRemove;
  final void Function(TripStop stop) onEditStop;
  final VoidCallback onAddStop;

  const RouteStopList({
    super.key,
    required this.stops,
    required this.onReorder,
    required this.onRemove,
    required this.onEditStop,
    required this.onAddStop,
  });

  @override
  Widget build(BuildContext context) {
    final pickup = stops.firstWhere((s) => s.type == StopType.pickup);
    final destination =
        stops.firstWhere((s) => s.type == StopType.destination);
    final intermediates =
        stops.where((s) => s.type == StopType.intermediate).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StopCard(
          stop: pickup,
          onTap: () => onEditStop(pickup),
          showDragHandle: false,
        ),
        const SizedBox(height: 10),
        if (intermediates.isNotEmpty) ...[
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              // Reorder within the intermediate slice; translate back to the
              // full list indices (pickup is always index 0, destination last).
              final fullOld = oldIndex + 1;
              final fullNew = newIndex + 1;
              onReorder(fullOld, fullNew);
            },
            proxyDecorator: (child, _, __) => Material(
              color: Colors.transparent,
              elevation: 6,
              borderRadius: BorderRadius.circular(10),
              child: child,
            ),
            itemCount: intermediates.length,
            itemBuilder: (context, index) {
              final stop = intermediates[index];
              return Padding(
                key: ValueKey(stop.id),
                padding: const EdgeInsets.only(bottom: 10),
                child: _StopCard(
                  stop: stop,
                  onTap: () => onEditStop(stop),
                  onRemove: () => onRemove(stop.id),
                  dragIndex: index,
                ),
              );
            },
          ),
        ],
        _AddStopCard(onTap: onAddStop),
        const SizedBox(height: 10),
        _StopCard(
          stop: destination,
          onTap: () => onEditStop(destination),
          showDragHandle: false,
        ),
      ],
    );
  }
}

// ── Individual stop card ─────────────────────────────────────────────────────

class _StopCard extends StatelessWidget {
  final TripStop stop;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool showDragHandle;
  final int? dragIndex;

  const _StopCard({
    required this.stop,
    required this.onTap,
    this.onRemove,
    this.showDragHandle = true,
    this.dragIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              _StopIndicator(type: stop.type),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stop.typeLabel,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stop.address,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 20, color: _error),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              if (showDragHandle && dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.drag_indicator_rounded,
                        size: 22, color: _textHint),
                  ),
                )
              else if (showDragHandle)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(Icons.drag_indicator_rounded,
                      size: 22, color: _textHint),
                )
              else
                const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gold filled dot for pickup, dark slate filled dot for stops, gold pin for
/// destination — mirrors the indicator set used elsewhere in the app.
class _StopIndicator extends StatelessWidget {
  final StopType type;
  const _StopIndicator({required this.type});

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case StopType.pickup:
        return _Ring(color: _gold, fillColor: _gold);
      case StopType.intermediate:
        return _Ring(color: _darkSlate, fillColor: Colors.white);
      case StopType.destination:
        return const Icon(Icons.location_on_rounded, color: _gold, size: 22);
    }
  }
}

class _Ring extends StatelessWidget {
  final Color color;
  final Color fillColor;
  const _Ring({required this.color, required this.fillColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(color: color, width: 2.5),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: fillColor == color ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}

// ── Add intermediate stop — dashed card ──────────────────────────────────────

class _AddStopCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddStopCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _goldLight,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: _gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Text(
              'Add intermediate stop...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _gold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
