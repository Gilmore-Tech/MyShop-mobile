/// Help-article CMS + legal-document models.
///
///   - REST: `/v1/support/help/*`, `/v1/legal/:slug`
///
/// Articles + legal docs ship as Markdown. The backend confirms the body
/// is sanitised — `flutter_markdown` does not render raw HTML by default,
/// so any tag soup will be inert.

/// One bucket of help articles — surfaced as a card on the support home.
class HelpCategory {
  const HelpCategory({
    required this.slug,
    required this.title,
    this.description,
    this.iconName,
    this.articleCount,
  });

  factory HelpCategory.fromJson(Map<String, dynamic> json) {
    return HelpCategory(
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      iconName: json['iconName'] as String?,
      articleCount: (json['articleCount'] as num?)?.toInt(),
    );
  }

  final String slug;
  final String title;
  final String? description;

  /// Backend-suggested icon hint (e.g. `'account_circle'`, `'credit_card'`).
  /// The mobile maps this to a `MaterialIcons` value — unrecognised hints
  /// fall back to a default.
  final String? iconName;

  /// Number of articles in this category. Optional — backend may omit if
  /// counting is expensive.
  final int? articleCount;
}

/// One help article. List endpoints return summary form (no [bodyMarkdown]);
/// the detail endpoint populates the body.
class HelpArticle {
  const HelpArticle({
    required this.slug,
    required this.title,
    this.summary,
    this.bodyMarkdown,
    this.categorySlug,
    this.categoryTitle,
    this.updatedAt,
  });

  factory HelpArticle.fromJson(Map<String, dynamic> json) {
    return HelpArticle(
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      summary: json['summary'] as String? ?? json['excerpt'] as String?,
      bodyMarkdown: json['bodyMarkdown'] as String? ?? json['body'] as String?,
      categorySlug: json['categorySlug'] as String?,
      categoryTitle: json['categoryTitle'] as String?,
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  final String slug;
  final String title;
  final String? summary;
  final String? bodyMarkdown;
  final String? categorySlug;
  final String? categoryTitle;
  final DateTime? updatedAt;

  bool get hasBody => bodyMarkdown != null && bodyMarkdown!.isNotEmpty;
}

/// A legal document — Terms, Privacy, etc. The viewer renders
/// [bodyMarkdown]; if [externalUrl] is set (e.g. third-party licenses),
/// the screen swaps to a single "Open in browser" CTA instead.
class LegalDocument {
  const LegalDocument({
    required this.slug,
    required this.title,
    required this.version,
    this.bodyMarkdown,
    this.externalUrl,
    this.effectiveAt,
  });

  factory LegalDocument.fromJson(Map<String, dynamic> json) {
    return LegalDocument(
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      version: json['version'] as String? ?? '1.0.0',
      bodyMarkdown: json['bodyMarkdown'] as String? ?? json['body'] as String?,
      externalUrl: json['externalUrl'] as String?,
      effectiveAt: _parseDate(json['effectiveAt']),
    );
  }

  final String slug;
  final String title;

  /// Semver-ish version string. When this changes, re-consent flows can
  /// trigger — that work is out of scope for v1 but the field is here so
  /// the model doesn't need a migration later.
  final String version;
  final String? bodyMarkdown;

  /// When set, the viewer forgoes markdown rendering and shows a single
  /// CTA that launches the URL in the system browser. Used for
  /// third-party licenses (huge file) and any externally hosted policy.
  final String? externalUrl;
  final DateTime? effectiveAt;

  bool get isExternal => externalUrl != null && externalUrl!.isNotEmpty;
  bool get hasBody => bodyMarkdown != null && bodyMarkdown!.isNotEmpty;
}

/// Canonical legal slugs the backend serves. Kept here so screens can
/// reference them without scattering string literals.
class LegalSlugs {
  const LegalSlugs._();

  static const terms = 'terms';
  static const privacy = 'privacy';
  static const acceptableUse = 'acceptable-use';
  static const communityGuidelines = 'community-guidelines';
  static const thirdPartyLicenses = 'third-party-licenses';
  static const cookiePolicy = 'cookie-policy';

  /// Order shown in the Legal & Policies list on the support home.
  static const ordered = <String>[
    terms,
    privacy,
    acceptableUse,
    communityGuidelines,
    thirdPartyLicenses,
    cookiePolicy,
  ];

  /// Display title fallback when the backend hasn't returned one yet
  /// (e.g. the support home is rendering the list before any doc has
  /// been fetched).
  static String fallbackTitle(String slug) {
    switch (slug) {
      case terms:
        return 'Terms of Service';
      case privacy:
        return 'Privacy Policy';
      case acceptableUse:
        return 'Acceptable Use Policy';
      case communityGuidelines:
        return 'Community Guidelines';
      case thirdPartyLicenses:
        return 'Third-Party Licenses';
      case cookiePolicy:
        return 'Cookie Policy';
      default:
        return slug;
    }
  }
}

DateTime? _parseDate(Object? raw) {
  if (raw is String) return DateTime.tryParse(raw);
  return null;
}
