import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

/// Release containment for the role-owned referral migration.
///
/// The screen deliberately performs no referral API call and exposes no code,
/// copy, or share action. This prevents a user from reasonably believing a
/// code will be linked while backend mutations are paused.
class ReferralScreen extends StatelessWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Referrals',
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
                  'Referral programme temporarily paused',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Referral codes are not being accepted or shared during this release. '
                  'Existing referral records and rewards remain safely stored.',
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
