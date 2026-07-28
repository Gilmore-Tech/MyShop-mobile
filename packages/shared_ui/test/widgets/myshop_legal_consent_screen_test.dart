import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

const _terms = LegalDocument(
  documentId: 'terms-id',
  slug: LegalSlugs.terms,
  title: 'Terms',
  version: '1',
  audience: 'client',
  bodyMarkdown: 'Terms',
  effectiveAt: null,
  publishedAt: null,
);

const _privacy = LegalDocument(
  documentId: 'privacy-id',
  slug: LegalSlugs.privacy,
  title: 'Privacy',
  version: '1',
  audience: 'client',
  bodyMarkdown: 'Privacy',
  effectiveAt: null,
  publishedAt: null,
);

const _loadedStatus = LegalConsentStatus(
  role: 'client',
  current: false,
  requiresConsent: true,
  hasActiveWork: false,
  missingSlugs: [LegalSlugs.terms, LegalSlugs.privacy],
  documents: [_terms, _privacy],
);

void main() {
  testWidgets('status-load failure is neutral and cannot encourage logout', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MyShopLegalConsentScreen(
          status: null,
          loading: false,
          submitting: false,
          error: Exception('DNS and internal server detail'),
          onRetry: () async => retries++,
          onOpenDocument: (_) {},
          onAccept: (_) async {},
          onSupport: () {},
          onLogout: () async {},
        ),
      ),
    );

    expect(find.textContaining('Terms and Privacy Notice'), findsNothing);
    expect(find.text('Log out'), findsNothing);
    expect(
      find.text(
        'We could not refresh this page. Please try again in a moment. '
        'Your current screen and session are unchanged.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('connection'), findsNothing);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('explicit legal review still offers logout', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MyShopLegalConsentScreen(
          status: _loadedStatus,
          loading: false,
          submitting: false,
          onRetry: () async {},
          onOpenDocument: (_) {},
          onAccept: (_) async {},
          onSupport: () {},
          onLogout: () async {},
        ),
      ),
    );

    expect(find.text('Review updated policies'), findsOneWidget);
    expect(find.text('Log out'), findsOneWidget);
  });

  testWidgets(
    'submission failure stays inline without losing documents or selections',
    (tester) async {
      var retries = 0;
      MyShopLegalSubmissionIssue? issue;
      late StateSetter updateHost;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              updateHost = setState;
              return MyShopLegalConsentScreen(
                status: _loadedStatus,
                loading: false,
                submitting: false,
                error: Exception('DROP TABLE users; PRIVATE_BACKEND_MESSAGE'),
                submissionIssue: issue,
                onRetry: () async => retries++,
                onOpenDocument: (_) {},
                onAccept: (_) async {},
                onSupport: () {},
                onLogout: () async {},
              );
            },
          ),
        ),
      );

      await tester.tap(find.byType(Checkbox).at(0));
      await tester.tap(find.byType(Checkbox).at(1));
      await tester.pump();

      updateHost(() => issue = MyShopLegalSubmissionIssue.unavailable);
      await tester.pump();

      expect(find.text('I accept the Terms of Service v1'), findsOneWidget);
      expect(find.text('I acknowledge the Privacy Notice v1'), findsOneWidget);
      expect(
        find.text(
          'We could not record your acceptance right now. '
          'Please try again in a moment.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('DROP TABLE'), findsNothing);
      expect(find.textContaining('PRIVATE_BACKEND_MESSAGE'), findsNothing);
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .map((checkbox) => checkbox.value),
        everyElement(isTrue),
      );

      await tester.tap(find.text('Refresh policies'));
      await tester.pump();
      expect(retries, 1);
    },
  );

  final issueCopy = <MyShopLegalSubmissionIssue, String>{
    MyShopLegalSubmissionIssue.offline:
        'No internet connection. Reconnect, then try accepting again.',
    MyShopLegalSubmissionIssue.timeout:
        'The connection timed out. Please try accepting again.',
    MyShopLegalSubmissionIssue.invalidSelection:
        'The policy versions changed or could not be accepted. '
            'Refresh the policies and try again.',
    MyShopLegalSubmissionIssue.unavailable:
        'We could not record your acceptance right now. '
            'Please try again in a moment.',
    MyShopLegalSubmissionIssue.confirmationPending:
        'We could not confirm your acceptance yet. '
            'Refresh the policies and try again.',
  };

  for (final entry in issueCopy.entries) {
    testWidgets('${entry.key.name} renders only fixed app-owned copy', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MyShopLegalConsentScreen(
            status: _loadedStatus,
            loading: false,
            submitting: false,
            error: Exception('malicious backend prose'),
            submissionIssue: entry.key,
            onRetry: () async {},
            onOpenDocument: (_) {},
            onAccept: (_) async {},
            onSupport: () {},
            onLogout: () async {},
          ),
        ),
      );

      expect(find.text(entry.value), findsOneWidget);
      expect(find.textContaining('malicious backend prose'), findsNothing);
    });
  }
}
