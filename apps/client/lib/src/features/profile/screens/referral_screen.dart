import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/referral_provider.dart';

class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    final referral = ref.watch(referralProvider);
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: MyShopColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Refer & Earn',
          style: TextStyle(
            color: MyShopColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: referral.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MyShopColors.primaryGold),
        ),
        error: (_, __) => _LoadError(
          onRetry: () => ref.invalidate(referralProvider),
        ),
        data: (data) => RefreshIndicator(
          color: MyShopColors.primaryGold,
          onRefresh: () => ref.refresh(referralProvider.future),
          child: ListView(
            padding: EdgeInsets.all(width * 0.05),
            children: [
              _RewardBanner(data: data),
              const SizedBox(height: 18),
              _CodeCard(data: data),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Referrals',
                      value: '${data.totalReferrals}',
                      icon: Icons.people_alt_rounded,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Earned',
                      value: 'GHS ${data.earnedGhs.toStringAsFixed(2)}',
                      icon: Icons.workspace_premium_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'How it works',
                style: TextStyle(
                  color: MyShopColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              const _HowItWorks(),
              if (data.recentReferrals.isNotEmpty) ...[
                const SizedBox(height: 24),
                const Text(
                  'Recent referrals',
                  style: TextStyle(
                    color: MyShopColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                ...data.recentReferrals.map(_ReferralTile.new),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardBanner extends StatelessWidget {
  const _RewardBanner({required this.data});

  final ReferralData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MyShopColors.primaryGold, MyShopColors.primaryGoldDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.card_giftcard_rounded,
              color: Colors.white, size: 34),
          const SizedBox(height: 12),
          Text(
            data.rewardPesewas > 0
                ? 'Earn GHS ${data.rewardGhs.toStringAsFixed(2)} per referral'
                : 'Invite people to MyShop',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Your reward is added after the referred role completes its first paid ride or job.',
            style: TextStyle(
              color: Colors.white.withAlpha(225),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.data});

  final ReferralData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          const Text(
            'Your client referral code',
            style: TextStyle(color: MyShopColors.textSecondary),
          ),
          const SizedBox(height: 10),
          SelectableText(
            data.code,
            style: const TextStyle(
              color: MyShopColors.textPrimary,
              fontSize: 23,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: data.code.isEmpty
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: data.code));
                          MyShopToast.show(context,
                              message: 'Referral code copied');
                        },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed:
                      data.code.isEmpty ? null : () => _share(context, data),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: MyShopColors.primaryGold,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text('Share'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context, ReferralData data) async {
    final link = data.shareLink?.trim();
    final reward = data.rewardPesewas > 0
        ? ' I earn GHS ${data.rewardGhs.toStringAsFixed(2)} after your first completed paid activity.'
        : '';
    final message = [
      'Join MyShop with my referral code ${data.code}.$reward',
      if (link != null && link.isNotEmpty) link,
    ].join('\n\n');
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(1, 1, 1, 1);
    await Share.share(message, sharePositionOrigin: origin);
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: MyShopColors.primaryGold),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: MyShopColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(label,
              style: const TextStyle(color: MyShopColors.textSecondary)),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('1', 'Share the code from this exact role account.'),
      ('2', 'The new client, driver or artisan enters it during registration.'),
      ('3', 'You earn once that exact role completes its first paid activity.'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: steps
            .map(
              (step) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 13,
                      backgroundColor: MyShopColors.primaryGoldLight,
                      child: Text(
                        step.$1,
                        style: const TextStyle(
                          color: MyShopColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        step.$2,
                        style: const TextStyle(
                          color: MyShopColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _ReferralTile extends StatelessWidget {
  const _ReferralTile(this.entry);

  final ReferralEntry entry;

  @override
  Widget build(BuildContext context) {
    final earned = entry.status == 'earned';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Row(
        children: [
          const CircleAvatar(child: Icon(Icons.person_rounded)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  entry.dateLabel,
                  style: const TextStyle(color: MyShopColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            earned
                ? '+GHS ${(entry.bonusPesewas / 100).toStringAsFixed(2)}'
                : 'Pending',
            style: TextStyle(
              color: earned ? MyShopColors.success : MyShopColors.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: MyShopColors.error, size: 48),
          const SizedBox(height: 10),
          const Text('Could not load your referral account.'),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
