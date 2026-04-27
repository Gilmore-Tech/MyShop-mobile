import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

// Design tokens — will migrate to MyShopColors once shared_ui is exported here.
const _goldSoft      = Color(0xFFFDF3E1); // subtle gold background for pin tap target

/// Home-screen pickup card.
///
/// Tapping the row opens the pickup search screen (autocomplete predictions).
/// The trailing gold map-pin chip opens the map pin picker for pickup.
class LocationSearchCard extends StatelessWidget {
  final String pickupLabel;

  final VoidCallback? onPickupTap;
  final VoidCallback? onPickupPinTap;

  const LocationSearchCard({
    super.key,
    required this.pickupLabel,
    this.onPickupTap,
    this.onPickupPinTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.036),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(vertical: w * 0.01),
      child: _LocationRow(
        leading: const _PickupDot(),
        valueLabel: 'Current: $pickupLabel',
        valueStyle: TextStyle(
          fontSize: w * 0.033,
          fontWeight: FontWeight.w600,
          color: MyShopColors.primaryGold,
        ),
        onTap: onPickupTap,
        onPinTap: onPickupPinTap,
        pinTooltip: 'Pick pickup on map',
      ),
    );
  }
}

// ── Row ──────────────────────────────────────────────────────────────────────

class _LocationRow extends StatelessWidget {
  final Widget leading;
  final String valueLabel;
  final TextStyle valueStyle;
  final VoidCallback? onTap;
  final VoidCallback? onPinTap;
  final String pinTooltip;

  const _LocationRow({
    required this.leading,
    required this.valueLabel,
    required this.valueStyle,
    this.onTap,
    this.onPinTap,
    required this.pinTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.026, vertical: h * 0.005),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(w * 0.02),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: w * 0.015,
                  vertical: h * 0.012,
                ),
                child: Row(
                  children: [
                    SizedBox(width: w * 0.051, child: Center(child: leading)),
                    SizedBox(width: w * 0.031),
                    Expanded(
                      child: Text(
                        valueLabel,
                        style: valueStyle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: w * 0.015),
          _PinChip(onTap: onPinTap, tooltip: pinTooltip),
        ],
      ),
    );
  }
}

// ── Pickup dot (hollow gold circle) ─────────────────────────────────────────

class _PickupDot extends StatelessWidget {
  const _PickupDot();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: w * 0.036,
      height: w * 0.036,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: MyShopColors.primaryGold, width: 2),
      ),
    );
  }
}

// ── Gold map-pin chip (inline at end of row) ────────────────────────────────

class _PinChip extends StatelessWidget {
  final VoidCallback? onTap;
  final String tooltip;

  const _PinChip({this.onTap, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: _goldSoft,
        borderRadius: BorderRadius.circular(w * 0.026),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(w * 0.026),
          child: SizedBox(
            width: w * 0.097,
            height: w * 0.097,
            child: Icon(Icons.location_on, color: MyShopColors.primaryGold, size: w * 0.051),
          ),
        ),
      ),
    );
  }
}
