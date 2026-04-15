import 'package:flutter/material.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textHint = Color(0xFFBDBDBD);
const _textSecondary = Color(0xFF555E68);
const _border = Color(0xFFE0E0E0);

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _FieldLabel(label: 'PICKUP LOCATION'),
        const SizedBox(height: 6),
        _PickupField(location: pickupLabel, onTap: onPickupTap),
        const SizedBox(height: 14),
        const _FieldLabel(label: 'DESTINATION'),
        const SizedBox(height: 6),
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
    return Text(
      label,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: _textSecondary,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const _PickupIndicator(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                location,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.location_on_outlined, color: _textSecondary, size: 20),
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
    final hasValue = label != null && label!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            const _DestinationIndicator(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hasValue ? label! : 'Where to?',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
                  color: hasValue ? _textPrimary : _textHint,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              onTap: onPinTap,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.location_on_outlined,
                    color: _textSecondary, size: 20),
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
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: _gold, width: 2.5),
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _gold,
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
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _border, width: 2),
      ),
    );
  }
}
