import 'package:flutter/material.dart';

// Design tokens — will migrate to MyShopColors / MyShopTypography once shared_ui is exported
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: _gold,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Current: $currentLocation',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _gold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          GestureDetector(
            onTap: onDestinationTap,
            child: const Icon(Icons.location_on, color: _gold, size: 20),
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
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.search, color: _textHint, size: 20),
            const SizedBox(width: 10),
            Text(
              'Where are you going?',
              style: const TextStyle(
                fontSize: 14,
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
