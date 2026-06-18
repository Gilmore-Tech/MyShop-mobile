/// Maps a backend `paymentMethod` wire value to a driver-facing label.
///
/// Mirrors the client app's `formatRidePaymentMethodLabel` so the method the
/// rider picked shows the same name on the driver's incoming request and the
/// trip-complete summary — never the raw wire value (e.g. `momo_telecel`).
String paymentMethodLabel(String? raw) {
  switch (raw) {
    case null:
    case '':
    case 'cash':
      return 'Cash';
    case 'momo_mtn':
    case 'mtn':
      return 'MTN Mobile Money';
    case 'momo_telecel':
      return 'Telecel Cash';
    case 'momo_airteltigo':
      return 'AT Cash';
    case 'card':
    case 'visa':
    case 'mastercard':
      return 'Card';
    case 'momo':
    case 'mobile_money':
      return 'Mobile Money';
    default:
      return raw;
  }
}
