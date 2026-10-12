import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/current_operational_region_provider.dart';

class OperationalAreaNotice extends StatelessWidget {
  const OperationalAreaNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MyShopColors.warningLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MyShopColors.warning.withValues(alpha: 0.35),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: MyShopColors.warning,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  operationalAreaUnavailableTitle,
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  operationalAreaUnavailableMessage,
                  style: TextStyle(
                    color: MyShopColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
