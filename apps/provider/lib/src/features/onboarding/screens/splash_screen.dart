import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Shown while the auth controller bootstraps from secure storage.
class ProviderSplashScreen extends StatelessWidget {
  const ProviderSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(MyShopColors.primaryGold),
        ),
      ),
    );
  }
}
