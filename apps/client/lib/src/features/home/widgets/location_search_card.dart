import 'package:flutter/material.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textHint = Color(0xFFBDBDBD);
const _divider = Color(0xFFE0E0E0);

class LocationSearchCard extends StatelessWidget {
  final String currentLocation;
  final VoidCallback? onSearchTap;
  final VoidCallback? onDestinationTap;

  const LocationSearchCard({
    super.key,
    required this.currentLocation,
    this.onSearchTap,
    this.onDestinationTap,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: w * 0.041),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(w * 0.031),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LocationRow(
            currentLocation: currentLocation,
            onDestinationTap: onDestinationTap,
          ),
          const Divider(height: 1, thickness: 1, color: _divider),
          _SearchRow(onTap: onSearchTap),
        ],
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final String currentLocation;
  final VoidCallback? onDestinationTap;

  const _LocationRow({required this.currentLocation, this.onDestinationTap});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.017),
      child: Row(
        children: [
          Container(
            width:  w * 0.026,
            height: w * 0.026,
            decoration: const BoxDecoration(
              color: _gold,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: w * 0.026),
          Expanded(
            child: Text(
              'Current: $currentLocation',
              style: TextStyle(
                fontSize: w * 0.033,
                fontWeight: FontWeight.w600,
                color: _gold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onDestinationTap,
            child: Icon(Icons.location_on, color: _gold, size: w * 0.051),
          ),
        ],
      ),
    );
  }
}

class _SearchRow extends StatelessWidget {
  final VoidCallback? onTap;

  const _SearchRow({this.onTap});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(bottom: Radius.circular(w * 0.031)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: w * 0.041, vertical: h * 0.017),
        child: Row(
          children: [
            Icon(Icons.search, color: _textHint, size: w * 0.051),
            SizedBox(width: w * 0.026),
            Text(
              'Where are you going?',
              style: TextStyle(
                fontSize: w * 0.036,
                fontWeight: FontWeight.w400,
                color: _textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
