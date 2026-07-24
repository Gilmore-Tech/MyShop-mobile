import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/provider_type_provider.dart';
import '../providers/referral_provider.dart';

class ProviderReferralScreen extends ConsumerWidget {
  const ProviderReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role =
        ref.watch(providerTypeProvider).isDriver ? 'driver' : 'artisan';
    final referral = ref.watch(providerReferralProvider);
    return Scaffold(
      backgroundColor: MyShopColors.offWhite,
      appBar: AppBar(
        backgroundColor: MyShopColors.surfaceWhite,
        leading: IconButton(
          onPressed: context.pop,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text('${role[0].toUpperCase()}${role.substring(1)} referrals'),
      ),
      body: referral.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: MyShopColors.primaryGold),
        ),
        error: (_, __) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load this role’s referral account.'),
              TextButton(
                onPressed: () => ref.invalidate(providerReferralProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (data) => RefreshIndicator(
          color: MyShopColors.primaryGold,
          onRefresh: () => ref.refresh(providerReferralProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      MyShopColors.primaryGold,
                      MyShopColors.primaryGoldDark,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.card_giftcard,
                        color: Colors.white, size: 36),
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
                      'This code and its rewards belong only to your $role account.',
                      style: TextStyle(color: Colors.white.withAlpha(225)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: MyShopColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: MyShopColors.divider),
                ),
                child: Column(
                  children: [
                    const Text(
                      'Your referral code',
                      style: TextStyle(color: MyShopColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    SelectableText(
                      data.code,
                      style: const TextStyle(
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
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: data.code));
                              MyShopToast.show(context,
                                  message: 'Referral code copied');
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: MyShopColors.primaryGold,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _share(context, data, role),
                            icon: const Icon(Icons.share),
                            label: const Text('Share'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ReferralStat(
                      label: 'Referrals',
                      value: '${data.totalReferrals}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReferralStat(
                      label: 'Earned',
                      value: 'GHS ${data.earnedGhs.toStringAsFixed(2)}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReferralStat(
                      label: 'Pending',
                      value: 'GHS ${data.pendingGhs.toStringAsFixed(2)}',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share(
    BuildContext context,
    ProviderReferralData data,
    String role,
  ) async {
    final link = data.shareLink?.trim();
    final message = [
      'Join MyShop with my $role referral code ${data.code}.',
      if (link != null && link.isNotEmpty) link,
    ].join('\n\n');
    final box = context.findRenderObject() as RenderBox?;
    final origin = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(1, 1, 1, 1);
    await Share.share(message, sharePositionOrigin: origin);
  }
}

class _ReferralStat extends StatelessWidget {
  const _ReferralStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: MyShopColors.surfaceWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MyShopColors.divider),
      ),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: MyShopColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
