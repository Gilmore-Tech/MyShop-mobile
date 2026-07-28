import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../../theme/myshop_colors.dart';
import '../../theme/myshop_spacing.dart';
import '../../theme/myshop_typography.dart';
import '../myshop_primary_button.dart';

/// Fixed, app-owned legal-acceptance outcomes that are safe to render.
///
/// Callers must classify transport and API failures into one of these values.
/// Backend messages, exception strings, response bodies, and machine codes are
/// deliberately not accepted by the consent form.
enum MyShopLegalSubmissionIssue {
  offline,
  timeout,
  invalidSelection,
  unavailable,
  confirmationPending,
}

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
    this.submissionIssue,
  });

  final LegalConsentStatus? status;
  final bool loading;
  final bool submitting;

  /// Status-load failures only. Their contents are never rendered.
  final Object? error;
  final MyShopLegalSubmissionIssue? submissionIssue;
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
  void initState() {
    super.initState();
    _documentSignature = _signature(widget.status);
  }

  @override
  void didUpdateWidget(covariant MyShopLegalConsentScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signature(widget.status);
    if (signature != _documentSignature) {
      _documentSignature = signature;
      _termsAccepted = false;
      _privacyAccepted = false;
    }
  }

  String _signature(LegalConsentStatus? status) =>
      status?.documents.map((document) => document.documentId).join('|') ?? '';

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
            Icons.cloud_off_outlined,
            size: 48,
            color: MyShopColors.error,
          ),
          const SizedBox(height: MyShopSpacing.md),
          const Text(
            'We could not refresh this page. Please try again in a moment. '
            'Your current screen and session are unchanged.',
            textAlign: TextAlign.center,
            style: MyShopTypography.body1,
          ),
          const SizedBox(height: MyShopSpacing.md),
          TextButton(onPressed: widget.onRetry, child: const Text('Retry')),
          TextButton(
            onPressed: widget.onSupport,
            child: const Text('Contact support'),
          ),
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
        if (widget.submissionIssue case final issue?) ...[
          const SizedBox(height: MyShopSpacing.md),
          _submissionNotice(issue),
        ],
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

  Widget _submissionNotice(MyShopLegalSubmissionIssue issue) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(MyShopSpacing.md),
        decoration: BoxDecoration(
          color: MyShopColors.error.withValues(alpha: 0.08),
          border: Border.all(color: MyShopColors.error.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  color: MyShopColors.error,
                  size: 20,
                ),
                const SizedBox(width: MyShopSpacing.sm),
                Expanded(
                  child: Text(
                    _submissionMessage(issue),
                    style: MyShopTypography.body2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: MyShopSpacing.xs),
            TextButton(
              onPressed: widget.submitting ? null : widget.onRetry,
              child: const Text('Refresh policies'),
            ),
          ],
        ),
      );

  String _submissionMessage(MyShopLegalSubmissionIssue issue) =>
      switch (issue) {
        MyShopLegalSubmissionIssue.offline =>
          'No internet connection. Reconnect, then try accepting again.',
        MyShopLegalSubmissionIssue.timeout =>
          'The connection timed out. Please try accepting again.',
        MyShopLegalSubmissionIssue.invalidSelection =>
          'The policy versions changed or could not be accepted. '
              'Refresh the policies and try again.',
        MyShopLegalSubmissionIssue.unavailable =>
          'We could not record your acceptance right now. '
              'Please try again in a moment.',
        MyShopLegalSubmissionIssue.confirmationPending =>
          'We could not confirm your acceptance yet. '
              'Refresh the policies and try again.',
      };

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
