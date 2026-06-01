import 'package:shared_models/shared_models.dart';

/// Surface-area config for the shared Support & Legal experience.
///
/// Both client and provider apps render the same widget tree; this object
/// flips the parts that differ between them — copy, default ticket
/// categories, contact channels, and navigation callbacks (so each app's
/// router stays the source of truth on routes).
class SupportLegalConfig {
  const SupportLegalConfig({
    required this.audience,
    required this.appName,
    required this.appVersion,
    required this.copyright,
    required this.supportEmail,
    required this.supportPhone,
    required this.whatsappNumber,
    required this.onOpenTickets,
    required this.onNewTicket,
    required this.onOpenCategory,
    required this.onOpenArticle,
    required this.onOpenSearch,
    required this.onOpenLegal,
    required this.onOpenContactSheet,
    this.logoAssetPath,
  });

  /// Selects which audience the backend serves articles + legal docs for.
  /// Also drives [TicketCategory] dropdown filtering on the new-ticket form.
  final SupportAudience audience;

  /// Display name used in the in-app footer (e.g. "MyShop Client App").
  final String appName;
  final String appVersion;
  final String copyright;

  /// Support contact channels.
  ///
  /// [whatsappNumber] is in E.164 form WITHOUT the leading `+` —
  /// `https://wa.me/<digits>` rejects the plus sign.
  final String supportEmail;
  final String supportPhone;
  final String whatsappNumber;

  // Navigation callbacks. The widgets do no routing themselves — each app
  // wires these to its GoRouter.

  /// User tapped "My tickets" on the support home. Should push the
  /// tickets list screen.
  final void Function() onOpenTickets;

  /// User tapped "Open a ticket" / "Report an issue". Should push the
  /// new-ticket form. The optional [TicketCategory] pre-selects the
  /// dropdown (e.g. when reaching here from the Report Issue card we
  /// pre-select [TicketCategory.bug]).
  final void Function(TicketCategory? preselectCategory) onNewTicket;

  /// User tapped a help-category card. Should push the category screen.
  final void Function(String categorySlug) onOpenCategory;

  /// User tapped a help article (from search results or a category list).
  final void Function(String articleSlug) onOpenArticle;

  /// User tapped the search affordance. Should push the search screen.
  final void Function(String? initialQuery) onOpenSearch;

  /// User tapped a legal-document row.
  final void Function(String slug) onOpenLegal;

  /// User tapped "Contact Support" — open the bottom sheet that exposes
  /// WhatsApp / phone / email / new-ticket.
  final void Function() onOpenContactSheet;

  /// Path to the host app's logo asset (declared in the app's pubspec).
  /// Rendered in the footer next to the app name. When null, a generic
  /// shopping-bag icon is shown instead.
  final String? logoAssetPath;
}
