import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/chat_controller_provider.dart';
import 'package:myshop_client/src/features/services/providers/artisan_live_location_provider.dart';
import 'package:myshop_client/src/features/services/screens/bid_detail_screen.dart';
import 'package:myshop_client/src/features/services/screens/job_detail_screen.dart';

class _DirectedJobService extends JobService {
  _DirectedJobService({required this.quoteSubmitted}) : super(Dio());

  final bool quoteSubmitted;

  @override
  Future<Map<String, dynamic>> getJob(String jobId) async => {
        'id': jobId,
        'title': 'Repair the kitchen sink',
        'description': 'Repair the leaking kitchen sink.',
        'status': 'admin_assigned',
        'addressText': 'Kumasi',
        'latitude': 0,
        'longitude': 0,
        'category': {'name': 'Plumbing'},
        'assignedArtisanId': 'artisan-1',
        'bidsCount': quoteSubmitted ? 1 : 0,
        'assignment': {
          'attemptId': 'attempt-1',
          'revision': quoteSubmitted ? 2 : 1,
          'phase': quoteSubmitted ? 'awaiting_client_accept' : 'awaiting_quote',
          'quoteDeadlineAt': '2026-08-30T12:00:00.000Z',
          'acceptDeadlineAt':
              quoteSubmitted ? '2026-08-30T12:30:00.000Z' : null,
        },
      };

  @override
  Future<List<dynamic>> getBids(String jobId) async => quoteSubmitted
      ? [
          {
            'id': 'bid-1',
            'status': 'submitted',
            'amountPesewas': 12000,
            'etaMinutes': 12,
            'durationMinutes': 60,
            'artisan': {
              'id': 'artisan-1',
              'name': 'Kofi Mensah',
              'specialty': 'Plumber',
              'isVerified': true,
            },
          },
        ]
      : const [];
}

Widget _app(JobService service, Widget home) => ProviderScope(
      overrides: [
        jobServiceProvider.overrideWithValue(service),
        chatControllerProvider.overrideWith((ref) async => null),
        artisanLiveLocationsProvider.overrideWith(
          (ref, jobId) => Stream.value(const {}),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: const Size(430, 900),
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        ),
        home: home,
      ),
    );

void main() {
  testWidgets('zero-bid directed job says the artisan is preparing a quote',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _DirectedJobService(quoteSubmitted: false);

    await tester.pumpWidget(
      _app(service, const JobDetailScreen(jobId: 'job-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Artisan is preparing your quote'), findsOneWidget);
    expect(find.text('View 0 Bids'), findsNothing);
    expect(find.text('Artisan Preparing Quote'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('client can accept the directed quote in admin_assigned status',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _DirectedJobService(quoteSubmitted: true);

    await tester.pumpWidget(
      _app(
        service,
        const BidDetailScreen(jobId: 'job-1', bidId: 'bid-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Accept Bid'), findsOneWidget);
    expect(find.text("You've already chosen an artisan for this job"),
        findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
