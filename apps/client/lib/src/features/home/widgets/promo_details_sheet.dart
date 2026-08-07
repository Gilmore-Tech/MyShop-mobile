import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

/// Modal bottom sheet with the full details of a promotional campaign.
///
/// Opened by tapping a banner in the home carousel. Visual idiom follows
/// the provider app's pay-commission sheet: rounded 20 top corners,
/// Raleway headings, gold accents.
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

  /// "15% off, up to GHS 10" (percentage with cap), "15% off" (no cap),
  /// or "GHS 5 off" (fixed — discountValue is in pesewas).
  static String discountHeadline(ActivePromoCampaign c) {
    if (c.isPercentage) {
      final pct = _trimNum(c.discountValue);
      final cap = c.maxDiscountPesewas;
      if (cap != null && cap > 0) {
        return '$pct% off, up to GHS ${_ghs(cap)}';
      }
      return '$pct% off';
    }
    return 'GHS ${_ghs(c.discountValue.round())} off';
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: h * 0.75),
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
                const _NewCustomersChip(),
              ],
              const SizedBox(height: 12),

              // Discount headline
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
                        discountHeadline(campaign),
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
                Flexible(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MyShopColors.surfaceGrey,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        campaign.termsText,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: MyShopColors.textSecondary,
                        ),
                      ),
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
    );
  }
}

class _NewCustomersChip extends StatelessWidget {
  const _NewCustomersChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: MyShopColors.infoLight,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'New customers only',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: MyShopColors.info,
        ),
      ),
    );
  }
}
