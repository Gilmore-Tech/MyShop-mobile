import 'package:url_launcher/url_launcher.dart';

/// Helpers for launching the four support contact channels.
///
/// Used by [MyShopContactSupportSheet]; exposed publicly so per-app code
/// (e.g. a payout-locked banner with "Contact support" inline) can hit
/// the same launchers without re-implementing them.
class SupportChannels {
  const SupportChannels._();

  /// `https://wa.me/<E.164 digits, no plus>` — opens the WhatsApp app
  /// pre-filled with [message] when set. Returns false if no handler is
  /// installed.
  static Future<bool> openWhatsApp({
    required String number,
    String? message,
  }) async {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return false;
    final uri = Uri.parse(
      'https://wa.me/$digits'
      '${message != null ? '?text=${Uri.encodeComponent(message)}' : ''}',
    );
    return _launch(uri);
  }

  /// `tel:` deeplink — Android dials immediately on tap, iOS prompts.
  static Future<bool> openPhone(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.isEmpty) return false;
    final uri = Uri(scheme: 'tel', path: cleaned);
    return _launch(uri);
  }

  /// `mailto:` — opens the user's default mail client.
  static Future<bool> openEmail({
    required String to,
    String? subject,
    String? body,
  }) async {
    final query = <String, String>{};
    if (subject != null) query['subject'] = subject;
    if (body != null) query['body'] = body;
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      query: query.isEmpty
          ? null
          : query.entries
              .map(
                (e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}',
              )
              .join('&'),
    );
    return _launch(uri);
  }

  /// Opens an arbitrary external URL in the system browser. Used by the
  /// legal viewer when a document has [LegalDocument.externalUrl] set
  /// (third-party licenses, externally hosted policies).
  static Future<bool> openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return _launch(uri);
  }

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
