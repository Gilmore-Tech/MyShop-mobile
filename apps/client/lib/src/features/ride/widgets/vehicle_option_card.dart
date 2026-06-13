import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/ride_provider.dart';

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
    final available = option.driversAvailable;
    // When no drivers are available the card is informational only — it shows
    // the fare but can't be picked. Gray it out, drop the tap handler, and
    // never paint it as selected so it reads as disabled (Semantics flag keeps
    // it non-color-dependent for screen readers).
    final selected = isSelected && available;

    return Semantics(
      enabled: available,
      selected: selected,
      child: Opacity(
        opacity: available ? 1.0 : 0.55,
        child: GestureDetector(
          onTap: available ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? MyShopColors.primaryGold
                        : MyShopColors.divider,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    _VehicleIcon(isMotorcycle: option.isMotorcycle),
                    const SizedBox(width: 12),
                    Expanded(child: _VehicleInfo(option: option)),
                    _FareInfo(option: option, isSelected: selected),
                  ],
                ),
              ),
              if (selected)
                const Positioned(
                  top: -6,
                  right: -6,
                  child: _SelectedBadge(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedBadge extends StatelessWidget {
  const _SelectedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: MyShopColors.primaryGold,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.check_rounded, color: Colors.white, size: 14),
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
      width: w * 0.144,
      height: h * 0.047,
      decoration: BoxDecoration(
        color: MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(w * 0.015),
      ),
      child: Icon(
        isMotorcycle ? Icons.two_wheeler_rounded : Icons.directions_car_rounded,
        size: isMotorcycle ? w * 0.067 : w * 0.077,
        color: MyShopColors.darkSlate,
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
                color: MyShopColors.textPrimary,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.person_outline_rounded,
                size: 13, color: MyShopColors.textSecondary),
            const SizedBox(width: 2),
            Text(
              '${option.capacityPersons}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: MyShopColors.textSecondary,
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
            color: MyShopColors.textSecondary,
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
            color: MyShopColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        if (!option.driversAvailable)
          // Replaces the ETA — there's no honest "x min" to show when no
          // driver is in range. Paired with an icon + text (not color alone).
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_off_outlined,
                size: 11,
                color: MyShopColors.error,
              ),
              SizedBox(width: 3),
              Text(
                'No drivers',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.error,
                ),
              ),
            ],
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_time_rounded,
                size: 11,
                color: isSelected
                    ? MyShopColors.primaryGold
                    : MyShopColors.textSecondary,
              ),
              const SizedBox(width: 3),
              Text(
                option.estimatedTime,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: isSelected
                      ? MyShopColors.primaryGold
                      : MyShopColors.textSecondary,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
