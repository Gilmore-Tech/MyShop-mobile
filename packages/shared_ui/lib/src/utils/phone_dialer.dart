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
  final sanitized = _sanitize(rawNumber);
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

/// Keeps a leading `+` (for the Ghana country code) and digits only — strips
/// the spaces / dashes / bullet characters numbers are often formatted with.
String _sanitize(String? raw) {
  if (raw == null) return '';
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  return hasPlus ? '+$digits' : digits;
}
