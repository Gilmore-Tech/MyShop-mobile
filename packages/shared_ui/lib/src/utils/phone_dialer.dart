import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/myshop_toast.dart';

/// Opens the device dialer pre-filled with [rawNumber] so the two sides of a
/// ride / job can reach each other directly.
///
/// During the pilot, the platform no longer masks counterparty numbers — the
/// backend serves the real, dialable number on active and recently-completed
/// bookings. This helper centralises the `tel:` launch + the user-facing
/// failure handling so every "Call" affordance behaves identically across
/// both apps.
///
/// Returns `true` when the dialer opened, `false` otherwise (empty number or
/// the platform refused the `tel:` intent). On failure a toast is shown when a
/// [context] is still mounted.
Future<bool> dialPhoneNumber(
  BuildContext context,
  String? rawNumber,
) async {
  final sanitized = normalizeDialablePhoneNumber(rawNumber);
  if (sanitized.isEmpty) {
    if (context.mounted) {
      MyShopToast.show(
        context,
        message: 'No phone number available',
        type: ToastType.error,
      );
    }
    return false;
  }

  final uri = Uri(scheme: 'tel', path: sanitized);
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      MyShopToast.show(
        context,
        message: 'Could not open the dialer',
        type: ToastType.error,
      );
    }
    return opened;
  } catch (_) {
    if (context.mounted) {
      MyShopToast.show(
        context,
        message: 'Could not open the dialer',
        type: ToastType.error,
      );
    }
    return false;
  }
}

/// Returns `true` when [raw] can be safely passed to a `tel:` URI.
bool isDialablePhoneNumber(String? raw) =>
    normalizeDialablePhoneNumber(raw).isNotEmpty;

/// Keeps a leading `+` (for country codes) and digits only, stripping spaces
/// and dashes. Masked display numbers are deliberately rejected so a string
/// like `+233 ••• ••• 67` never becomes the partial, unusable `+23367`.
String normalizeDialablePhoneNumber(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim().replaceFirst(
        RegExp(r'^tel:', caseSensitive: false),
        '',
      );
  if (trimmed.isEmpty) return '';
  if (RegExp(r'[•*xX…]').hasMatch(trimmed)) return '';

  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  if (digits.length < 9) return '';
  if (!hasPlus && digits.startsWith('00') && digits.length > 10) {
    return '+${digits.substring(2)}';
  }
  return hasPlus ? '+$digits' : digits;
}
