import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/auth_controller.dart';

/// Shown when a phone number has both driver and artisan accounts.
/// The user picks which role to sign in as, then OTP is sent.
class SignInRoleSelectionScreen extends ConsumerStatefulWidget {
  const SignInRoleSelectionScreen({super.key});

  @override
  ConsumerState<SignInRoleSelectionScreen> createState() =>
      _SignInRoleSelectionScreenState();
}

class _SignInRoleSelectionScreenState
    extends ConsumerState<SignInRoleSelectionScreen> {
  bool _takeoverDialogVisible = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);

    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next is AuthTakeoverPrompt && !_takeoverDialogVisible) {
        _takeoverDialogVisible = true;
        _showTakeoverDialog(context, next.phone);
      } else if (next is! AuthTakeoverPrompt && _takeoverDialogVisible) {
        _takeoverDialogVisible = false;
        if (Navigator.canPop(context)) Navigator.pop(context);
      }
    });

    String? error;
    bool isLoading = false;

    if (state is AuthRoleSelection) {
      error = state.error;
      isLoading = state.isLoading;
    } else if (state is AuthTakeoverPrompt) {
      isLoading = state.isLoading;
    }

    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        elevation: 0,
        foregroundColor: MyShopColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () =>
              ref.read(authControllerProvider.notifier).reset(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text('Choose your account', style: MyShopTypography.h1),
              const SizedBox(height: 8),
              Text(
                'This phone number has multiple accounts. '
                'Which one would you like to sign in to?',
                style: MyShopTypography.body2,
              ),
              const SizedBox(height: 32),
              _RoleOption(
                icon: Icons.directions_car_filled_rounded,
                title: 'Driver',
                subtitle: 'Pick up rides and earn on your schedule',
                accent: MyShopColors.darkSlate,
                isLoading: isLoading,
                onTap: isLoading
                    ? null
                    : () => ref
                        .read(authControllerProvider.notifier)
                        .selectRoleAndLogin(role: 'driver'),
              ),
              const SizedBox(height: 16),
              _RoleOption(
                icon: Icons.handyman_rounded,
                title: 'Artisan',
                subtitle: 'Bid on jobs and offer skilled services',
                accent: MyShopColors.primaryGoldDark,
                isLoading: isLoading,
                onTap: isLoading
                    ? null
                    : () => ref
                        .read(authControllerProvider.notifier)
                        .selectRoleAndLogin(role: 'artisan'),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Text(
                  error,
                  style: MyShopTypography.caption
                      .copyWith(color: MyShopColors.error),
                  textAlign: TextAlign.center,
                ),
              ],
              if (isLoading) ...[
                const SizedBox(height: 24),
                const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTakeoverDialog(BuildContext context, String phone) async {
    final controller = ref.read(authControllerProvider.notifier);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Already signed in elsewhere'),
        content: Text(
          'This account ($phone) is signed in on another device. '
          'Continue here? The other device will be signed out.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.cancelTakeover();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.confirmTakeover();
            },
            child: const Text('Continue here'),
          ),
        ],
      ),
    );
    _takeoverDialogVisible = false;
  }
}

class _RoleOption extends StatelessWidget {
  const _RoleOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.isLoading,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isLoading ? 0.6 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: MyShopColors.surfaceWhite,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: MyShopColors.divider),
              boxShadow: [
                BoxShadow(
                  color: MyShopColors.darkText.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 28, color: accent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: MyShopTypography.h3),
                      const SizedBox(height: 2),
                      Text(subtitle, style: MyShopTypography.body2),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: MyShopColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
