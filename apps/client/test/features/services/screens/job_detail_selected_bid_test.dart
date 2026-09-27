import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/services/screens/job_detail_screen.dart';

class _SelectedBidJobService extends JobService {
  _SelectedBidJobService({required this.selected}) : super(Dio());

  final bool selected;

  @override
  Future<Map<String, dynamic>> getJob(String jobId) async => {
        'id': jobId,
        'title': 'Repair the kitchen sink',
        'description': 'Repair the leaking kitchen sink.',
        'status': selected ? 'confirmed' : 'open',
        'addressText': 'Kumasi',
        'latitude': 6.6885,
        'longitude': -1.6244,
        'category': {'name': 'Plumbing'},
        if (selected) 'assignedArtisanId': 'artisan-user-1',
        if (selected)
          'acceptedBid': {
            'id': 'bid-accepted-1',
            'amountPesewas': 12000,
            'durationMinutes': 120,
          },
        'bidsCount': selected ? 1 : 2,
      };

  @override
  Future<List<dynamic>> getBids(String jobId) async => selected
      ? [
          {
            'bidId': 'bid-accepted-1',
            'status': 'accepted',
            'amountPesewas': 12000,
            'etaMinutes': 12,
            'durationMinutes': 120,
            'artisan': {
              // This profile ID deliberately differs from assignedArtisanId.
              'id': 'artisan-profile-1',
              'name': 'Kofi Mensah',
            },
          },
        ]
      : [
          for (var index = 1; index <= 2; index++)
            {
              'bidId': 'bid-$index',
              'status': 'pending',
              'amountPesewas': 10000 + index,
              'etaMinutes': 10,
              'durationMinutes': 60,
              'artisan': {
                'id': 'artisan-$index',
                'name': 'Artisan $index',
              },
            },
        ];
}

Widget _app(JobService service) {
  final router = GoRouter(
    initialLocation: '/services/job/job-1',
    routes: [
      GoRoute(
        path: '/services/job/:jobId',
        builder: (_, state) => JobDetailScreen(
          jobId: state.pathParameters['jobId']!,
        ),
      ),
      GoRoute(
        path: '/services/job/:jobId/bids/:bidId',
        builder: (_, state) => Scaffold(
          body: Text('Opened ${state.pathParameters['bidId']}'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [jobServiceProvider.overrideWithValue(service)],
    child: MaterialApp.router(
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          size: const Size(430, 900),
          textScaler: TextScaler.noScaling,
        ),
        child: child!,
      ),
    ),
  );
}

void main() {
  testWidgets('selected quote stays clickable across artisan ID namespaces',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(_SelectedBidJobService(selected: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Loading selected quote…'), findsNothing);
    expect(find.text('View Selected Quote'), findsOneWidget);

    await tester.tap(find.text('View Selected Quote'));
    await tester.pumpAndSettle();

    expect(find.text('Opened bid-accepted-1'), findsOneWidget);
  });

  testWidgets('unselected request keeps the existing bid-count button',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _app(_SelectedBidJobService(selected: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('View 2 Bids'), findsOneWidget);
    expect(find.text('View Selected Quote'), findsNothing);
  });
}
