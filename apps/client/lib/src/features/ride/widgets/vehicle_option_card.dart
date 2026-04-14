import 'package:flutter/material.dart';
import '../providers/ride_provider.dart';

// Design tokens
const _gold = Color(0xFFF5A623);
const _textPrimary = Color(0xFF161A1D);
const _textSecondary = Color(0xFF555E68);
const _border = Color(0xFFE0E0E0);
const _surfaceGrey = Color(0xFFF3F5F6);

class VehicleOptionCard extends StatelessWidget {
  final VehicleOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const VehicleOptionCard({
    super.key,
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? _gold : _border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            _VehicleIcon(isMotorcycle: option.isMotorcycle),
            const SizedBox(width: 12),
            Expanded(child: _VehicleInfo(option: option)),
            _FareInfo(option: option, isSelected: isSelected),
          ],
        ),
      ),
    );
  }
}

class _VehicleIcon extends StatelessWidget {
  final bool isMotorcycle;
  const _VehicleIcon({required this.isMotorcycle});

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      width:  w * 0.144,
      height: h * 0.047,
      decoration: BoxDecoration(
        color: _surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.015),
      ),
      child: Icon(
        isMotorcycle ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
        size: isMotorcycle ? w * 0.067 : w * 0.077,
        color: const Color(0xFF46535D),
      ),
    );
  }
}

class _VehicleInfo extends StatelessWidget {
  final VehicleOption option;
  const _VehicleInfo({required this.option});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              option.name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.person_outline_rounded,
                size: 13, color: _textSecondary),
            const SizedBox(width: 2),
            Text(
              '${option.capacityPersons}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: _textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          option.description,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: _textSecondary,
          ),
        ),
      ],
    );
  }
}

class _FareInfo extends StatelessWidget {
  final VehicleOption option;
  final bool isSelected;

  const _FareInfo({required this.option, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          option.fareDisplay,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.access_time_rounded,
              size: 11,
              color: isSelected ? _gold : _textSecondary,
            ),
            const SizedBox(width: 3),
            Text(
              option.estimatedTime,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isSelected ? _gold : _textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
