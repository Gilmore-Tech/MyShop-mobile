import 'package:flutter/material.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textHint = Color(0xFFBDBDBD);
const _textSecondary = Color(0xFF555E68);
const _border = Color(0xFFE0E0E0);

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
    final h = MediaQuery.sizeOf(context).height;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(label: 'PICKUP LOCATION'),
        SizedBox(height: h * 0.007),
        _PickupField(location: pickupLocation),
        SizedBox(height: h * 0.017),
        _FieldLabel(label: 'DESTINATION'),
        SizedBox(height: h * 0.007),
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
    final w = MediaQuery.sizeOf(context).width;
    return Text(
      label,
      style: TextStyle(
        fontSize: w * 0.026,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      height: h * 0.057,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.021),
        border: Border.all(color: _border),
      ),
      padding: EdgeInsets.symmetric(horizontal: w * 0.031),
      child: Row(
        children: [
          Container(
            width:  w * 0.046,
            height: w * 0.046,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _gold, width: 2),
            ),
          ),
          SizedBox(width: w * 0.026),
          Expanded(
            child: Text(
              location,
              style: TextStyle(
                fontSize: w * 0.036,
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
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      height: h * 0.057,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.021),
        border: Border.all(color: _border),
      ),
      padding: EdgeInsets.symmetric(horizontal: w * 0.031),
      child: Row(
        children: [
          Container(
            width:  w * 0.041,
            height: w * 0.041,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(w * 0.005),
              border: Border.all(color: _textSecondary, width: 2),
            ),
          ),
          SizedBox(width: w * 0.026),
          Expanded(
            child: TextField(
              controller: controller,
              onTap: onTap,
              readOnly: onTap != null,
              style: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: _textPrimary,
              ),
              decoration: InputDecoration(
                hintText: 'Where to?',
                hintStyle: TextStyle(
                  fontSize: w * 0.036,
                  fontWeight: FontWeight.w400,
                  color: _textHint,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          Icon(Icons.location_on_outlined, color: _gold, size: w * 0.051),
        ],
      ),
    );
  }
}
