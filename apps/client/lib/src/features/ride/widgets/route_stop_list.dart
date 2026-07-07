import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/edit_trip_provider.dart';

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
  final bool allowEndpointEditing;

  const RouteStopList({
    super.key,
    required this.stops,
    required this.onReorder,
    required this.onRemove,
    required this.onEditStop,
    required this.onAddStop,
    this.allowEndpointEditing = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    // The provider seeds asynchronously (postFrameCallback) so the very
    // first build can run with an empty list. Bail with a thin loading
    // sliver in that case — `firstWhere` would otherwise throw
    // `Bad state: No element` and crash the screen as it opens.
    final pickup = stops
        .cast<TripStop?>()
        .firstWhere((s) => s?.type == StopType.pickup, orElse: () => null);
    final destination = stops
        .cast<TripStop?>()
        .firstWhere((s) => s?.type == StopType.destination, orElse: () => null);
    if (pickup == null || destination == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final intermediates =
        stops.where((s) => s.type == StopType.intermediate).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StopCard(
          stop: pickup,
          onTap: allowEndpointEditing ? () => onEditStop(pickup) : null,
          showDragHandle: false,
        ),
        SizedBox(height: w * 0.026),
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
              borderRadius: BorderRadius.circular(w * 0.026),
              child: child,
            ),
            itemCount: intermediates.length,
            itemBuilder: (context, index) {
              final stop = intermediates[index];
              final canEdit = stop.isPendingNewStop;
              return Padding(
                key: ValueKey(stop.id),
                padding: EdgeInsets.only(bottom: w * 0.026),
                child: _StopCard(
                  stop: stop,
                  onTap: canEdit ? () => onEditStop(stop) : null,
                  onRemove: canEdit ? () => onRemove(stop.id) : null,
                  showDragHandle: canEdit,
                  dragIndex: canEdit ? index : null,
                ),
              );
            },
          ),
        ],
        _AddStopCard(onTap: onAddStop),
        SizedBox(height: w * 0.026),
        _StopCard(
          stop: destination,
          onTap: allowEndpointEditing ? () => onEditStop(destination) : null,
          showDragHandle: false,
        ),
      ],
    );
  }
}

// ── Individual stop card ─────────────────────────────────────────────────────

class _StopCard extends StatelessWidget {
  final TripStop stop;
  final VoidCallback? onTap;
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(w * 0.026),
        child: Container(
          padding: EdgeInsets.fromLTRB(
            w * 0.036,
            h * 0.012,
            w * 0.021,
            h * 0.012,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(w * 0.026),
            border: Border.all(color: MyShopColors.divider),
          ),
          child: Row(
            children: [
              _StopIndicator(type: stop.type),
              SizedBox(width: w * 0.031),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      stop.typeLabel,
                      style: TextStyle(
                        fontSize: w * 0.026,
                        fontWeight: FontWeight.w800,
                        color: MyShopColors.textSecondary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: h * 0.0025),
                    Text(
                      stop.address,
                      style: TextStyle(
                        fontSize: w * 0.036,
                        fontWeight: FontWeight.w600,
                        color: MyShopColors.textPrimary,
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
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    size: w * 0.051,
                    color: MyShopColors.error,
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(
                    minWidth: w * 0.082,
                    minHeight: w * 0.082,
                  ),
                ),
              if (showDragHandle && dragIndex != null)
                ReorderableDragStartListener(
                  index: dragIndex!,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: w * 0.015),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: w * 0.056,
                      color: MyShopColors.textHint,
                    ),
                  ),
                )
              else if (showDragHandle)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: w * 0.015),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: w * 0.056,
                    color: MyShopColors.textHint,
                  ),
                )
              else
                SizedBox(width: w * 0.015),
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
    final w = MediaQuery.sizeOf(context).width;
    switch (type) {
      case StopType.pickup:
        return const _Ring(
            color: MyShopColors.primaryGold,
            fillColor: MyShopColors.primaryGold);
      case StopType.intermediate:
        return const _Ring(
            color: MyShopColors.darkSlate, fillColor: Colors.white);
      case StopType.destination:
        return Icon(Icons.location_on_rounded,
            color: MyShopColors.primaryGold, size: w * 0.056);
    }
  }
}

class _Ring extends StatelessWidget {
  final Color color;
  final Color fillColor;
  const _Ring({required this.color, required this.fillColor});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: w * 0.046,
      height: w * 0.046,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fillColor,
        border: Border.all(color: color, width: 2.5),
      ),
      child: Center(
        child: Container(
          width: w * 0.015,
          height: w * 0.015,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(w * 0.026),
      child: Container(
        height: h * 0.059,
        padding: EdgeInsets.symmetric(horizontal: w * 0.036),
        decoration: BoxDecoration(
          color: MyShopColors.primaryGoldLight,
          borderRadius: BorderRadius.circular(w * 0.026),
          border: Border.all(
              color: MyShopColors.primaryGold.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: w * 0.056,
              height: w * 0.056,
              decoration: const BoxDecoration(
                color: MyShopColors.primaryGold,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, size: w * 0.036, color: Colors.white),
            ),
            SizedBox(width: w * 0.031),
            Text(
              'Add intermediate stop...',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w600,
                color: MyShopColors.primaryGold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
