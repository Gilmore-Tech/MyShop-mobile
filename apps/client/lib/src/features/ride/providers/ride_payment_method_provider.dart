import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

/// Rider's chosen payment method for the next ride request.
///
/// Today the rider picks between cash (driver collects at end of trip) and
/// in-app via MTN Mobile Money — the most common Ghana use case. The
/// backend's `CreateRideDto` accepts five values (cash, card, momo_mtn,
/// momo_telecel, momo_airteltigo); we expose two here and wire the rest as
/// the UI evolves. Adding more is just an extra enum value + branch in
/// [RidePaymentMethodX.wireValue]/[label].
enum RidePaymentMethod {
  /// Cash — driver collects at the end of the trip; no Paystack charge.
  cash,

  /// MTN Mobile Money — pre-trip choice, charged via Paystack on completion.
  momoMtn,

  /// Telecel Cash (formerly Vodafone Cash) — charged via Paystack on completion.
  momoTelecel,

  /// AT Cash (AirtelTigo Money) — charged via Paystack on completion.
  momoAirtelTigo,
}

extension RidePaymentMethodX on RidePaymentMethod {
  /// Wire value sent to `POST /v1/rides` (`paymentMethod` field). Matches
  /// the backend `PaymentMethod` enum in
  /// `apps/api/src/modules/ride/dto/create-ride.dto.ts`.
  String get wireValue => switch (this) {
        RidePaymentMethod.cash => 'cash',
        RidePaymentMethod.momoMtn => 'momo_mtn',
        RidePaymentMethod.momoTelecel => 'momo_telecel',
        RidePaymentMethod.momoAirtelTigo => 'momo_airteltigo',
      };

  /// Short display label for screens that only have room for the name
  /// (matching screen, tracking sheet, receipt header).
  String get label => switch (this) {
        RidePaymentMethod.cash => 'Cash',
        RidePaymentMethod.momoMtn => 'MTN Mobile Money',
        RidePaymentMethod.momoTelecel => 'Telecel Cash',
        RidePaymentMethod.momoAirtelTigo => 'AT Cash',
      };

  /// One-line subtitle used on the picker sheet.
  String get subtitle => switch (this) {
        RidePaymentMethod.cash => 'Pay the driver in cash at the end',
        RidePaymentMethod.momoMtn =>
          'Charged on your MTN line when the trip ends',
        RidePaymentMethod.momoTelecel =>
          'Charged on your Telecel line when the trip ends',
        RidePaymentMethod.momoAirtelTigo =>
          'Charged on your AirtelTigo line when the trip ends',
      };

  IconData get icon => switch (this) {
        RidePaymentMethod.cash => Icons.payments_outlined,
        RidePaymentMethod.momoMtn => Icons.smartphone_outlined,
        RidePaymentMethod.momoTelecel => Icons.smartphone_outlined,
        RidePaymentMethod.momoAirtelTigo => Icons.smartphone_outlined,
      };

  /// Whether the rider needs to settle a Paystack charge after the trip.
  /// Every method except cash is charged in-app via Paystack.
  bool get isInApp => this != RidePaymentMethod.cash;
}

/// Inverse of [RidePaymentMethodX.wireValue]. Used to project the
/// authoritative `paymentMethod` field on the `ride:state` snapshot back
/// onto a rider-facing display label, so the choice the rider made flows
/// through every downstream screen via the same lookup.
RidePaymentMethod? ridePaymentMethodFromWire(String? wire) {
  switch (wire) {
    case 'cash':
      return RidePaymentMethod.cash;
    case 'momo_mtn':
      return RidePaymentMethod.momoMtn;
    case 'momo_telecel':
      return RidePaymentMethod.momoTelecel;
    case 'momo_airteltigo':
      return RidePaymentMethod.momoAirtelTigo;
    default:
      return null;
  }
}

/// Map any backend payment-method string (canonical wire values, plus
/// historic free-text variants) to a clean rider-facing label.
///
/// The matching/tracking/receipt screens read `MatchedDriver.paymentMethod`
/// and `RideReceipt.paymentMethod` straight off the snapshot; that field is
/// raw backend wire shape (`cash`, `momo_mtn`, etc.) — this is the single
/// place we translate to display copy so we don't end up showing
/// "momo_mtn" on the tracking card.
String formatRidePaymentMethodLabel(String? raw) {
  final mapped = ridePaymentMethodFromWire(raw);
  if (mapped != null) return mapped.label;
  switch (raw) {
    case null:
    case '':
      return 'Cash';
    case 'momo_telecel':
      return 'Telecel Cash';
    case 'momo_airteltigo':
      return 'AirtelTigo Money';
    case 'card':
    case 'visa':
    case 'mastercard':
      return 'Card';
    case 'mobile_money':
    case 'momo':
      return 'Mobile Money';
    default:
      return raw;
  }
}

/// Rider's pre-trip selection. Cash by default — matches the existing
/// (silent) behaviour and avoids the in-app charge step until the rider
/// explicitly opts in.
final selectedRidePaymentMethodProvider =
    StateProvider<RidePaymentMethod>((_) => RidePaymentMethod.cash);

/// Bottom sheet that lets the rider switch between cash and in-app for the
/// next ride. Keeps the picker logic close to the enum so adding a method
/// (e.g. Telecel) is a single-file change.
Future<RidePaymentMethod?> showRidePaymentMethodSheet(
  BuildContext context,
  RidePaymentMethod current,
) {
  return showModalBottomSheet<RidePaymentMethod>(
    context: context,
    backgroundColor: MyShopColors.surfaceWhite,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: MyShopColors.divider,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Payment method',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: MyShopColors.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final method in RidePaymentMethod.values)
            _MethodTile(
              method: method,
              selected: method == current,
              onTap: () => Navigator.of(sheetCtx).pop(method),
            ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final RidePaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: MyShopColors.surfaceGrey,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                method.icon,
                size: 20,
                color: MyShopColors.textPrimary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: MyShopColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    method.subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: MyShopColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 22,
              color: selected
                  ? MyShopColors.primaryGold
                  : MyShopColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
