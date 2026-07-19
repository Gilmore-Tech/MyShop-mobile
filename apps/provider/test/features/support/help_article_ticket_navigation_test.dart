import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myshop_provider/src/features/support/providers/support_providers.dart';
import 'package:myshop_provider/src/features/support/screens/help_article_route_screen.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  testWidgets('help article opens the new-ticket route instead of popping', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/help/article',
      routes: [
        GoRoute(
          path: '/help/article',
          builder: (_, __) => const HelpArticleRouteScreen(slug: 'recovery'),
        ),
        GoRoute(
          path: '/account/support/tickets/new',
          builder: (_, state) => Scaffold(
            key: const ValueKey('provider-new-ticket-route'),
            body: Text(
              ((state.extra as Map<String, Object?>?)?['preselectedCategory']
                          as TicketCategory?)
                      ?.wire ??
                  'none',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          helpArticleProvider.overrideWith(
            (ref, slug) async => const HelpArticle(
              slug: 'recovery',
              title: 'Account recovery',
              bodyMarkdown: 'Recovery help.',
            ),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    final contact = find.text('Still need help? Contact support');
    await tester.ensureVisible(contact);
    await tester.tap(contact);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open a ticket'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('provider-new-ticket-route')),
      findsOneWidget,
    );
    expect(find.text('other'), findsOneWidget);
  });
}
