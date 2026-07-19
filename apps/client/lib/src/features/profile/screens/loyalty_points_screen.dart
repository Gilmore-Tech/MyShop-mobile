import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// Release containment for the role-owned loyalty-ledger migration.
///
/// No balance or history request is made here: the preserved legacy ledger is
/// keyed to the private phone identity and could expose sibling-role activity.
class LoyaltyPointsScreen extends StatelessWidget {
  const LoyaltyPointsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: context.pop,
        ),
        title: Text(
          'Loyalty Points',
          style: TextStyle(
            color: MyShopColors.textPrimary,
            fontSize: width * 0.044,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(width * 0.06),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.all(width * 0.06),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MyShopColors.divider),
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.pause_circle_outline_rounded,
                  size: 52,
                  color: MyShopColors.primaryGold,
                ),
                SizedBox(height: 16),
                Text(
                  'Loyalty programme temporarily paused',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Earning, redemption, balances, and history are unavailable while each role receives its own secure ledger. Existing balances and records remain safely stored.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MyShopColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
