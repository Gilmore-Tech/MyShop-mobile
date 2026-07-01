import 'package:api_client/api_client.dart' show ApiException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/di/providers.dart';
import '../../auth/providers/auth_controller.dart';

/// Deactivate Account confirmation screen — explains consequences,
/// surfaces blocking status checks, and offers Continue / Keep My
/// Account actions. Continue fires `DELETE /v1/users/me` (soft-delete
/// with 90-day retention per the backend's UserService) and logs the
/// provider out so the GoRouter redirect drops them on the auth
/// screen.
///
/// Mandatory for Apple Guideline 5.1.1(v): every app with a sign-up
/// flow must offer in-app account deletion. The button was previously
/// a no-op (`onContinue: () {}`), which would have triggered an
/// automatic rejection at App Review.
///
/// PRD Reference: PRD 5.5 — provider account closure flow.
class DeactivateAccountScreen extends ConsumerStatefulWidget {
  const DeactivateAccountScreen({super.key});

  @override
  ConsumerState<DeactivateAccountScreen> createState() =>
      _DeactivateAccountScreenState();
}

class _DeactivateAccountScreenState
    extends ConsumerState<DeactivateAccountScreen> {
  bool _isDeleting = false;
  String? _errorMessage;

  Future<void> _confirmAndDelete() async {
    if (_isDeleting) return;

    // Two-step confirmation — the dialog is the second deliberate
    // tap. Without it, an accidental brush against the red "Continue"
    // button would wipe the account. Apple doesn't require the dialog
    // but every other ride-hailing/marketplace app uses one and
    // App Review's reviewers expect it.
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently disables your provider profile and '
          'removes your access. The action cannot be undone. '
          'Type-DEL identity records are retained for 90 days for '
          'dispute resolution, then purged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: MyShopColors.error),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await ref.read(userServiceProvider).deleteAccount();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _errorMessage = e.message.isNotEmpty
            ? e.message
            : "Couldn't delete your account. Please try again.";
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
        _errorMessage = "Couldn't delete your account. Please try again.";
      });
      return;
    }

    // Server confirms account is gone. Clear local auth state so the
    // router redirect drops us at the auth screen.
    try {
      await ref.read(authControllerProvider.notifier).logout();
    } catch (_) {/* best-effort; tokens are stale either way */}
    if (!mounted) return;
    // The router redirect handles navigation once auth flips to
    // unauthenticated. Just pop the screen so the user doesn't see a
    // momentary flash of the deactivate UI on the way out.
    context.go('/signin/phone');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      body: SafeArea(
        child: Column(
          children: [
            _Header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                  MyShopSpacing.md,
                  MyShopSpacing.lg,
                ),
                children: [
                  const _WarningHero(),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _SectionLabel(text: 'CONSEQUENCES OF DEACTIVATION'),
                  const SizedBox(height: MyShopSpacing.sm),
                  _ConsequencesCard(),
                  const SizedBox(height: MyShopSpacing.lg),
                  const _DataRetentionNote(),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: MyShopSpacing.md),
                    _ErrorBanner(message: _errorMessage!),
                  ],
                  const SizedBox(height: MyShopSpacing.lg),
                ],
              ),
            ),
            _Footer(
              isDeleting: _isDeleting,
              onContinue: _confirmAndDelete,
              onKeep: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: MyShopColors.error),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: MyShopTypography.body2
                  .copyWith(color: MyShopColors.error, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        MyShopSpacing.sm,
        MyShopSpacing.sm,
        MyShopSpacing.md,
        MyShopSpacing.md,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(bottom: BorderSide(color: MyShopColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
            onPressed: () => context.pop(),
          ),
          Text(
            'Deactivate Account',
            style: MyShopTypography.h1.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Warning hero
// ─────────────────────────────────────────────────────────────────────────────

class _WarningHero extends StatelessWidget {
  const _WarningHero();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: const BoxDecoration(
            color: MyShopColors.errorLight,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.warning_amber_rounded,
            size: 44,
            color: MyShopColors.error,
          ),
        ),
        const SizedBox(height: MyShopSpacing.md),
        Text(
          'Are you sure?',
          style: MyShopTypography.h1.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 24,
          ),
        ),
        const SizedBox(height: MyShopSpacing.sm),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MyShopSpacing.lg),
          child: Text(
            'This will permanently disable your provider profile and remove your access.',
            textAlign: TextAlign.center,
            style: MyShopTypography.body1.copyWith(
              color: MyShopColors.textSecondary,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MyShopTypography.overline.copyWith(
        color: MyShopColors.textSecondary,
        fontWeight: FontWeight.w900,
        fontSize: 12,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Consequences card
// ─────────────────────────────────────────────────────────────────────────────

class _ConsequencesCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const items = [
      _Consequence(
        icon: Icons.history,
        title: 'Loss of Work History',
        body:
            'Your track record of 450+ completed jobs will be permanently deleted.',
      ),
      _Consequence(
        icon: Icons.star_border,
        title: 'Reputation Wipe',
        body:
            'Your 4.9-star rating and all 128 verified customer reviews will disappear.',
      ),
      _Consequence(
        icon: Icons.gpp_maybe_outlined,
        title: 'Verification Status',
        body:
            'Your KYC and Police Clearance status will be revoked. Re-applying requires full fees.',
      ),
      _Consequence(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Financial History',
        body:
            'You will lose access to your historical earnings reports and tax documents.',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            _ConsequenceRow(item: items[i]),
            if (i < items.length - 1)
              const Divider(
                height: 1,
                indent: MyShopSpacing.md,
                endIndent: MyShopSpacing.md,
                color: MyShopColors.divider,
              ),
          ],
        ],
      ),
    );
  }
}

class _Consequence {
  const _Consequence({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _ConsequenceRow extends StatelessWidget {
  const _ConsequenceRow({required this.item});

  final _Consequence item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: MyShopColors.surfaceGrey,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(item.icon, size: 20, color: MyShopColors.textPrimary),
          ),
          const SizedBox(width: MyShopSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: MyShopTypography.h3.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.body,
                  style: MyShopTypography.body2.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// `_PendingPayoutsCard` removed — it carried hardcoded fake data
// ("GHS 420.50") and a "Go to Payouts" link bound to `() {}` that
// Apple would flag as either misleading content or a non-functional
// CTA. When pending-payouts gating becomes a real check, wire it back
// against `paymentServiceProvider.getCashCommissionOwed` / the
// payouts summary.

// ─────────────────────────────────────────────────────────────────────────────
// Data retention note
// ─────────────────────────────────────────────────────────────────────────────

class _DataRetentionNote extends StatelessWidget {
  const _DataRetentionNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MyShopSpacing.md),
      decoration: BoxDecoration(
        color: MyShopColors.offWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            size: 18,
            color: MyShopColors.textSecondary,
          ),
          const SizedBox(width: MyShopSpacing.sm),
          Expanded(
            child: Text(
              'Data retention policy: We retain certain financial records for up to 7 years to comply with Ghanaian tax laws and regulatory audit requirements.',
              style: MyShopTypography.body2.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky footer
// ─────────────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.isDeleting,
    required this.onContinue,
    required this.onKeep,
  });

  final bool isDeleting;
  final VoidCallback onContinue;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md,
        MyShopSpacing.md + MediaQuery.of(context).padding.bottom * 0.2,
      ),
      decoration: const BoxDecoration(
        color: MyShopColors.surfaceWhite,
        border: Border(top: BorderSide(color: MyShopColors.divider)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: isDeleting ? null : onContinue,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDeleting
                    ? MyShopColors.error.withValues(alpha: 0.6)
                    : MyShopColors.error,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: isDeleting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            MyShopColors.textOnPrimary),
                      ),
                    )
                  : Text(
                      'Delete my account',
                      style: MyShopTypography.button.copyWith(
                        color: MyShopColors.textOnPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: MyShopSpacing.sm),
          GestureDetector(
            onTap: isDeleting ? null : onKeep,
            child: Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceWhite,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MyShopColors.divider),
              ),
              alignment: Alignment.center,
              child: Text(
                'Keep my account',
                style: MyShopTypography.button.copyWith(
                  color: MyShopColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
