import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import '../myshop_primary_button.dart';

class MyShopLegalConsentScreen extends StatefulWidget {
  const MyShopLegalConsentScreen({
    super.key,
    required this.status,
    required this.loading,
    required this.submitting,
    required this.onRetry,
    required this.onOpenDocument,
    required this.onAccept,
    required this.onSupport,
    required this.onLogout,
    this.error,
  });

  final LegalConsentStatus? status;
  final bool loading;
  final bool submitting;
  final Object? error;
  final Future<void> Function() onRetry;
  final ValueChanged<LegalDocument> onOpenDocument;
  final Future<void> Function(List<LegalAcceptanceSelection>) onAccept;
  final VoidCallback onSupport;
  final Future<void> Function() onLogout;

  @override
  State<MyShopLegalConsentScreen> createState() =>
      _MyShopLegalConsentScreenState();
}

class _MyShopLegalConsentScreenState extends State<MyShopLegalConsentScreen> {
  bool _termsAccepted = false;
  bool _privacyAccepted = false;
  String _documentSignature = '';

  @override
  void didUpdateWidget(covariant MyShopLegalConsentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = widget.status?.documents
            .map((document) => document.documentId)
            .join('|') ??
        '';
    if (signature != _documentSignature) {
      _documentSignature = signature;
      _termsAccepted = false;
      _privacyAccepted = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    return Scaffold(
      backgroundColor: MyShopColors.surfaceWhite,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Review updated policies'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MyShopSpacing.lg),
          child: widget.loading && status == null
              ? const Center(child: CircularProgressIndicator())
              : widget.error != null && status == null
                  ? _error()
                  : _content(status),
        ),
      ),
    );
  }

  Widget _error() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.policy_outlined,
            size: 48,
            color: MyShopColors.error,
          ),
          const SizedBox(height: MyShopSpacing.md),
          const Text(
            'We could not verify the current Terms and Privacy Notice. New work remains paused.',
            textAlign: TextAlign.center,
            style: MyShopTypography.body1,
          ),
          const SizedBox(height: MyShopSpacing.md),
          TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
          TextButton(
            onPressed: widget.onSupport,
            child: const Text('Contact support'),
          ),
          TextButton(onPressed: widget.onLogout, child: const Text('Log out')),
        ],
      );

  Widget _content(LegalConsentStatus? status) {
    if (status == null || status.documents.length != 2) return _error();
    final terms = _document(status.documents, LegalSlugs.terms);
    final privacy = _document(status.documents, LegalSlugs.privacy);
    if (terms == null || privacy == null) return _error();

    return ListView(
      children: [
        const Icon(
          Icons.gavel_outlined,
          size: 52,
          color: MyShopColors.primaryGoldDark,
        ),
        const SizedBox(height: MyShopSpacing.md),
        const Text(
          'Before starting new work',
          textAlign: TextAlign.center,
          style: MyShopTypography.h2,
        ),
        const SizedBox(height: MyShopSpacing.sm),
        const Text(
          'Review and explicitly accept each current document. Active rides or jobs can still be completed, and safety, support, and logout remain available.',
          textAlign: TextAlign.center,
          style: MyShopTypography.body2,
        ),
        const SizedBox(height: MyShopSpacing.lg),
        _row(
          value: _termsAccepted,
          label: 'I accept the Terms of Service v${terms.version}',
          document: terms,
          onChanged: (value) => setState(() => _termsAccepted = value),
        ),
        _row(
          value: _privacyAccepted,
          label: 'I acknowledge the Privacy Notice v${privacy.version}',
          document: privacy,
          onChanged: (value) => setState(() => _privacyAccepted = value),
        ),
        const SizedBox(height: MyShopSpacing.lg),
        MyShopPrimaryButton(
          label: widget.submitting ? 'Recording…' : 'Accept and continue',
          onPressed: !widget.submitting && _termsAccepted && _privacyAccepted
              ? () => widget.onAccept([
                    LegalAcceptanceSelection.fromDocument(terms),
                    LegalAcceptanceSelection.fromDocument(privacy),
                  ])
              : null,
        ),
        const SizedBox(height: MyShopSpacing.sm),
        TextButton(
          onPressed: widget.onSupport,
          child: const Text('Contact support'),
        ),
        TextButton(
          onPressed: widget.submitting ? null : widget.onLogout,
          child: const Text('Log out'),
        ),
      ],
    );
  }

  Widget _row({
    required bool value,
    required String label,
    required LegalDocument document,
    required ValueChanged<bool> onChanged,
  }) =>
      Row(
        children: [
          Checkbox(
            value: value,
            onChanged: (next) => onChanged(next ?? false),
            activeColor: MyShopColors.primaryGold,
          ),
          Expanded(
            child: TextButton(
              onPressed: () => widget.onOpenDocument(document),
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              child: Text(
                label,
                style: MyShopTypography.body2.copyWith(
                  color: MyShopColors.primaryGoldDark,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      );

  LegalDocument? _document(List<LegalDocument> documents, String slug) {
    for (final document in documents) {
      if (document.slug == slug) return document;
    }
    return null;
  }
}
