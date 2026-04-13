import 'package:flutter/material.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textHint = Color(0xFFBDBDBD);
const _textSecondary = Color(0xFF555E68);
const _border = Color(0xFFE0E0E0);
const _surfaceGrey = Color(0xFFF3F5F6);

class PickupDestinationFields extends StatelessWidget {
  final String pickupLocation;
  final TextEditingController destinationController;
  final VoidCallback? onDestinationTap;

  const PickupDestinationFields({
    super.key,
    required this.pickupLocation,
    required this.destinationController,
    this.onDestinationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(label: 'PICKUP LOCATION'),
        const SizedBox(height: 6),
        _PickupField(location: pickupLocation),
        const SizedBox(height: 14),
        _FieldLabel(label: 'DESTINATION'),
        const SizedBox(height: 6),
        _DestinationField(
          controller: destinationController,
          onTap: onDestinationTap,
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
  const _PickupField({required this.location});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _gold, width: 2),
            ),
          ),
          const SizedBox(width: 10),
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
        ],
      ),
    );
  }
}

class _DestinationField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;

  const _DestinationField({required this.controller, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: _textSecondary, width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              onTap: onTap,
              readOnly: onTap != null,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: _textPrimary,
              ),
              decoration: const InputDecoration(
                hintText: 'Where to?',
                hintStyle: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: _textHint,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const Icon(Icons.location_on_outlined, color: _gold, size: 20),
        ],
      ),
    );
  }
}
