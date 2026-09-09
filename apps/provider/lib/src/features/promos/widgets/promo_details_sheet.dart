import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

/// Modal bottom sheet with the full details of a provider-audience
/// promotional campaign and its server-authoritative progress.
///
/// Opened by tapping a banner in the home carousel or the earnings
/// callout. Visual idiom mirrors the pay-commission sheet: rounded 20
/// top corners, Raleway headings, gold accents.
Future<void> showPromoDetailsSheet(
  BuildContext context,
  ActivePromoCampaign campaign,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: MyShopColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => PromoDetailsSheet(campaign: campaign),
  );
}

class PromoDetailsSheet extends StatelessWidget {
  const PromoDetailsSheet({super.key, required this.campaign});

  final ActivePromoCampaign campaign;

  /// "50% commission relief, up to GHS 15 per booking" (with cap) or
  /// "50% commission relief" (no cap). `discountValue` is the percent of
  /// the platform commission forgiven (1-100).
  static String reliefHeadline(ActivePromoCampaign c) {
    final pct = _trimNum(c.discountValue);
    final cap = c.maxDiscountPesewas;
    if (cap != null && cap > 0) {
      return '$pct% commission relief, up to GHS ${_ghs(cap)} per booking';
    }
    return '$pct% commission relief';
  }

  static String rewardHeadline(ActivePromoCampaign c) {
    final progress = c.providerPromo;
    if (progress == null) return reliefHeadline(c);
    if (progress.isCommissionRelief) {
      return '${progress.rewardValue}% commission relief';
    }
    if (progress.isGuaranteedEarnings) {
      return 'GHS ${_ghs(progress.rewardValue)} guaranteed earnings';
    }
    return 'GHS ${_ghs(progress.rewardValue)} cash reward';
  }

  static String _trimNum(num value) {
    final d = value.toDouble();
    return d == d.truncateToDouble()
        ? d.toStringAsFixed(0)
        : d.toStringAsFixed(1);
  }

  static String _ghs(int pesewas) {
    final ghs = pesewas / 100;
    return ghs == ghs.truncateToDouble()
        ? ghs.toStringAsFixed(0)
        : ghs.toStringAsFixed(2);
  }

  static String? validityLabel(ActivePromoCampaign c) {
    final fmt = DateFormat('d MMM yyyy');
    final starts = c.startsAt;
    final ends = c.endsAt;
    if (starts != null && ends != null) {
      return 'Valid ${fmt.format(starts.toLocal())} – '
          '${fmt.format(ends.toLocal())}';
    }
    if (ends != null) return 'Valid until ${fmt.format(ends.toLocal())}';
    if (starts != null) return 'Valid from ${fmt.format(starts.toLocal())}';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final validity = validityLabel(campaign);
    final progress = campaign.providerPromo;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * 0.75),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Grab handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: MyShopColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Campaign name
                Text(
                  campaign.name,
                  style: const TextStyle(
                    fontFamily: 'Raleway',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: MyShopColors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                if (campaign.newClientsOnly) ...[
                  const SizedBox(height: 8),
                  const _NewProvidersChip(),
                ],
                const SizedBox(height: 12),

                // Relief headline
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: MyShopColors.primaryGoldLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.local_offer_rounded,
                        size: 18,
                        color: MyShopColors.primaryGoldDark,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          rewardHeadline(campaign),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: MyShopColors.primaryGoldDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress == null
                      ? 'You keep more of every fare — the platform takes a smaller cut'
                      : progress.isCommissionRelief
                          ? 'Complete every selected target to earn back the configured share of commission.'
                          : progress.isGuaranteedEarnings
                              ? 'Complete every selected target. After the campaign ends, any shortfall below the guarantee is added as a reward.'
                              : 'Complete every selected target to earn this reward.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: MyShopColors.textPrimary,
                  ),
                ),

                if (progress != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'YOUR PROGRESS',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (progress.completedBookingsTarget != null)
                    _TargetRow(
                      complete: progress.bookingsComplete,
                      title: 'Completed trips / jobs',
                      value: '${progress.completedBookings} of '
                          '${progress.completedBookingsTarget}',
                    ),
                  if (progress.verifiedOnlineMinutesTarget != null)
                    _TargetRow(
                      complete: progress.onlineTimeComplete,
                      title: 'Verified online time',
                      value:
                          '${(progress.verifiedOnlineSeconds / 3600).toStringAsFixed(1)} of '
                          '${(progress.verifiedOnlineMinutesTarget! / 60).toStringAsFixed(1)} hours',
                    ),
                  if (progress.generatedRevenueTargetPesewas != null)
                    _TargetRow(
                      complete: progress.revenueComplete,
                      title: 'Revenue generated',
                      value: 'GHS ${_ghs(progress.generatedRevenuePesewas)} of '
                          'GHS ${_ghs(progress.generatedRevenueTargetPesewas!)}',
                    ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress.overallProgress,
                      minHeight: 7,
                      backgroundColor: MyShopColors.surfaceGrey,
                      color: progress.qualified
                          ? MyShopColors.success
                          : MyShopColors.primaryGold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettlementPanel(progress: progress),
                ],

                if (campaign.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    campaign.description,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],

                if (validity != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.event_rounded,
                        size: 14,
                        color: MyShopColors.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        validity,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],

                if (campaign.termsText.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'TERMS & CONDITIONS',
                    style: TextStyle(
                      fontFamily: 'Raleway',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textSecondary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      campaign.termsText,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: MyShopColors.textSecondary,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyShopColors.primaryGold,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'GOT IT',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
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

class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.complete,
    required this.title,
    required this.value,
  });

  final bool complete;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            complete
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            size: 18,
            color: complete ? MyShopColors.success : MyShopColors.textSecondary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: MyShopColors.textPrimary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MyShopColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettlementPanel extends StatelessWidget {
  const _SettlementPanel({required this.progress});

  final ProviderPromoProgress progress;

  String get _message {
    switch (progress.settlementStatus) {
      case 'awaiting_campaign_end':
        return 'Requirements complete. Your guaranteed-earnings top-up is calculated after the campaign ends.';
      case 'available':
        return 'GHS ${PromoDetailsSheet._ghs(progress.withdrawableRewardPesewas ?? 0)} is available in your earnings balance.';
      case 'reserved':
        return 'Your reward is included in a withdrawal that is being processed.';
      case 'paid':
        return 'This reward has been paid.';
      case 'debt_offset':
        return 'This reward was fully applied to the amount you owed.';
      case 'guarantee_met':
        return 'Your qualifying earnings already met the guarantee, so no top-up was needed.';
      case 'needs_review':
        return 'This reward is under review and is not available for another withdrawal.';
      default:
        return progress.qualified
            ? 'Requirements complete. The reward is being reconciled safely.'
            : 'Complete all selected targets to qualify.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final deducted = progress.deductionsAppliedPesewas ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: progress.qualified
            ? MyShopColors.successLight
            : MyShopColors.surfaceGrey,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _message,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w700,
              color: MyShopColors.textPrimary,
            ),
          ),
          if (deducted > 0) ...[
            const SizedBox(height: 5),
            Text(
              'GHS ${PromoDetailsSheet._ghs(deducted)} was applied to outstanding deductions first.',
              style: const TextStyle(
                fontSize: 11,
                height: 1.4,
                color: MyShopColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewProvidersChip extends StatelessWidget {
  const _NewProvidersChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: MyShopColors.infoLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'New providers only',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: MyShopColors.info,
        ),
      ),
    );
  }
}
