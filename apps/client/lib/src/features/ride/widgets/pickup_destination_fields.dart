import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Two tappable read-only rows used on the Plan Your Trip screen.
///
/// Tapping either field opens the destination search screen for that slot.
/// The trailing pin icon on the destination row opens the map pin picker.
class PickupDestinationFields extends StatelessWidget {
  final String pickupLabel;
  final String? destinationLabel;

  final VoidCallback? onPickupTap;
  final VoidCallback? onDestinationTap;
  final VoidCallback? onDestinationPinTap;

  const PickupDestinationFields({
    super.key,
    required this.pickupLabel,
    this.destinationLabel,
    this.onPickupTap,
    this.onDestinationTap,
    this.onDestinationPinTap,
  });

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FieldLabel(label: 'PICKUP LOCATION'),
        SizedBox(height: h * 0.007),
        _PickupField(location: pickupLabel, onTap: onPickupTap),
        SizedBox(height: h * 0.017),
        const _FieldLabel(label: 'DESTINATION'),
        SizedBox(height: h * 0.007),
        _DestinationField(
          label: destinationLabel,
          onTap: onDestinationTap,
          onPinTap: onDestinationPinTap,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Text(
      label,
      style: TextStyle(
        fontSize: w * 0.026,
        fontWeight: FontWeight.w900,
        color: MyShopColors.textSecondary,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _PickupField extends StatelessWidget {
  final String location;
  final VoidCallback? onTap;
  const _PickupField({required this.location, this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(w * 0.026),
      child: Container(
        height: h * 0.062,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * 0.026),
          border: Border.all(color: MyShopColors.divider),
        ),
        padding: EdgeInsets.symmetric(horizontal: w * 0.036),
        child: Row(
          children: [
            const _PickupIndicator(),
            SizedBox(width: w * 0.031),
            Expanded(
              child: Text(
                location,
                style: TextStyle(
                  fontSize: w * 0.036,
                  fontWeight: FontWeight.w500,
                  color: MyShopColors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.location_on_outlined,
              color: MyShopColors.textSecondary,
              size: w * 0.051,
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationField extends StatelessWidget {
  final String? label;
  final VoidCallback? onTap;
  final VoidCallback? onPinTap;

  const _DestinationField({this.label, this.onTap, this.onPinTap});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    final hasValue = label != null && label!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(w * 0.026),
      child: Container(
        height: h * 0.062,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(w * 0.026),
          border: Border.all(color: MyShopColors.divider),
        ),
        padding: EdgeInsets.symmetric(horizontal: w * 0.036),
        child: Row(
          children: [
            const _DestinationIndicator(),
            SizedBox(width: w * 0.031),
            Expanded(
              child: Text(
                hasValue ? label! : 'Where to?',
                style: TextStyle(
                  fontSize: w * 0.036,
                  fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                  color: hasValue
                      ? MyShopColors.textPrimary
                      : MyShopColors.textHint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onPinTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.only(left: w * 0.021),
                child: Icon(
                  Icons.location_on_outlined,
                  color: MyShopColors.textSecondary,
                  size: w * 0.051,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Gold outer ring + gold inner dot — reads as a "selected" pickup marker.
class _PickupIndicator extends StatelessWidget {
  const _PickupIndicator();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: w * 0.051,
      height: w * 0.051,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: MyShopColors.primaryGold, width: 2.5),
      ),
      child: Center(
        child: Container(
          width: w * 0.021,
          height: w * 0.021,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: MyShopColors.primaryGold,
          ),
        ),
      ),
    );
  }
}

// Empty rounded-corner square — reads as an unfilled destination slot.
class _DestinationIndicator extends StatelessWidget {
  const _DestinationIndicator();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      width: w * 0.046,
      height: w * 0.046,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(w * 0.010),
        border: Border.all(color: MyShopColors.divider, width: 2),
      ),
    );
  }
}
