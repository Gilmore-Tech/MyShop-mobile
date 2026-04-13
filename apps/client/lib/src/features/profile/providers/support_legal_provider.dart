import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Help Topic ────────────────────────────────────────────────────────────────

class HelpTopic {
  final String id;
  final String title;
  const HelpTopic({required this.id, required this.title});
}

const kHelpTopics = <HelpTopic>[
  HelpTopic(id: 'account_access',    title: 'Account Access'),
  HelpTopic(id: 'payments_billing',  title: 'Payments & Billing'),
  HelpTopic(id: 'privacy_safety',    title: 'Privacy & Safety'),
  HelpTopic(id: 'fraud_prevention',  title: 'Fraud Prevention'),
];

// ── Legal Item ────────────────────────────────────────────────────────────────

class LegalItem {
  final String id;
  final String title;
  final bool   isExternal; // opens browser instead of in-app WebView
  const LegalItem({
    required this.id,
    required this.title,
    this.isExternal = false,
  });
}

const kLegalItems = <LegalItem>[
  LegalItem(id: 'terms_of_service',     title: 'Terms of Service'),
  LegalItem(id: 'privacy_policy',       title: 'Privacy Policy'),
  LegalItem(id: 'acceptable_use',       title: 'Acceptable Use Policy'),
  LegalItem(id: 'community_guidelines', title: 'Community Guidelines'),
  LegalItem(id: 'third_party_licenses', title: 'Third-Party Licenses',
      isExternal: true),
  LegalItem(id: 'cookie_settings',      title: 'Cookie Settings'),
];

const kCommonSearches = <String>['Refund policy', 'Account safety'];

// ── State ─────────────────────────────────────────────────────────────────────
// Search is client-side filter only in v1 — no server-side help search endpoint.
// Contact Support → in-app chat or deep-link to WhatsApp support.
// Report an Issue → POST /v1/support/issues  { category, description, screenshots? }

class SupportLegalState {
  final String searchQuery;

  const SupportLegalState({this.searchQuery = ''});

  SupportLegalState copyWith({String? searchQuery}) =>
      SupportLegalState(searchQuery: searchQuery ?? this.searchQuery);
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class SupportLegalNotifier extends StateNotifier<SupportLegalState> {
  SupportLegalNotifier() : super(const SupportLegalState());

  void updateSearch(String query) =>
      state = state.copyWith(searchQuery: query);

  void clearSearch() => state = state.copyWith(searchQuery: '');
}

final supportLegalProvider =
    StateNotifierProvider.autoDispose<SupportLegalNotifier, SupportLegalState>(
  (_) => SupportLegalNotifier(),
);
