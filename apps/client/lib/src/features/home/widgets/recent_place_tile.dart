import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import '../providers/home_provider.dart';

class RecentPlaceTile extends StatelessWidget {
  final RecentPlace place;
  final VoidCallback? onTap;

  const RecentPlaceTile({super.key, required this.place, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                const Icon(Icons.access_time_rounded,
                    color: MyShopColors.primaryGold, size: 22),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        place.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: MyShopColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        place.address,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: MyShopColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: MyShopColors.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        const Divider(
          height: 1,
          thickness: 1,
          indent: 52,
          endIndent: 16,
          color: MyShopColors.divider,
        ),
      ],
    );
  }
}
