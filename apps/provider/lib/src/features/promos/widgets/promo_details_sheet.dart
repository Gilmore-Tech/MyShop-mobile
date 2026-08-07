import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_ui/shared_ui.dart';

/// Modal bottom sheet with the full details of a provider-audience
/// promotional campaign (commission relief).
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
                        reliefHeadline(campaign),
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
              const Text(
                'You keep more of every fare — the platform takes a '
                'smaller cut',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: MyShopColors.textPrimary,
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
