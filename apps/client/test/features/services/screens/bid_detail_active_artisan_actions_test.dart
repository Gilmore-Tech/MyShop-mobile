import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/core/providers/chat_controller_provider.dart';
import 'package:myshop_client/src/features/services/providers/artisan_live_location_provider.dart';
import 'package:myshop_client/src/features/services/providers/job_detail_provider.dart';
import 'package:myshop_client/src/features/services/screens/bid_detail_screen.dart';

class _FakeJobService extends JobService {
  _FakeJobService() : super(Dio());

  String status = 'in_progress';
  String? clientPaymentAcknowledgedAt;

  @override
  Future<Map<String, dynamic>> getJob(String jobId) async => {
        'id': jobId,
        'title': 'Repair the kitchen sink',
        'description': 'Repair the leaking kitchen sink.',
        'status': status,
        if (clientPaymentAcknowledgedAt != null)
          'clientPaymentAcknowledgedAt': clientPaymentAcknowledgedAt,
        'addressText': 'Kumasi',
        'latitude': 6.6885,
        'longitude': -1.6244,
        'category': {'name': 'Plumbing'},
        'artisan': {
          'id': 'artisan-1',
          'name': 'Kofi Mensah',
          'phone': '+233501234567',
          'verificationStatus': 'approved',
        },
        'acceptedBid': {
          'id': 'bid-1',
          'amountPesewas': 12000,
          'etaMinutes': 12,
          'durationMinutes': 60,
        },
      };

  @override
  Future<List<dynamic>> getBids(String jobId) async => [
        {
          'id': 'bid-1',
          'status': 'accepted',
          'amountPesewas': 12000,
          'etaMinutes': 12,
          'durationMinutes': 60,
          'artisan': {
            'id': 'artisan-1',
            'name': 'Kofi Mensah',
            'specialty': 'Plumber',
            'isVerified': true,
            'latitude': 6.6900,
            'longitude': -1.6200,
          },
        },
      ];
}

void main() {
  testWidgets(
    'accepted bid shows the live artisan stage and both call choices',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _FakeJobService();

      await tester.pumpWidget(
        ProviderScope(
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
              ),
              child: child!,
            ),
            home: const BidDetailScreen(jobId: 'job-1', bidId: 'bid-1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Work In Progress'), findsOneWidget);
      expect(find.text('Bid Confirmed'), findsNothing);
      expect(find.bySemanticsLabel('Call artisan'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Call artisan'));
      await tester.pumpAndSettle();

      expect(find.text('Call in app'), findsOneWidget);
      expect(find.text('Phone call'), findsOneWidget);
      expect(find.text('+233501234567'), findsOneWidget);

      Navigator.of(tester.element(find.text('Call in app'))).pop();
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(BidDetailScreen)),
      );
      final stageCases = <String, String>{
        'artisan_en_route': 'Artisan En Route',
        'arrived': 'Artisan Arrived',
        'in_progress': 'Work In Progress',
        'artisan_marked_complete': 'Review Completion',
        'pending_payment': 'Payment Processing',
        'completed': 'Job Completed',
        'cancelled': 'Job Cancelled',
      };
      for (final stage in stageCases.entries) {
        service
          ..status = stage.key
          ..clientPaymentAcknowledgedAt = null;
        container.invalidate(jobDetailProvider('job-1'));
        await tester.pumpAndSettle();
        expect(find.text(stage.value), findsOneWidget);
      }

      // Cash acknowledgement keeps the backend at artisan_marked_complete,
      // but the client-facing stage must still advance to payment processing.
      service
        ..status = 'artisan_marked_complete'
        ..clientPaymentAcknowledgedAt = '2026-07-20T12:00:00Z';
      container.invalidate(jobDetailProvider('job-1'));
      await tester.pumpAndSettle();
      expect(find.text('Payment Processing'), findsOneWidget);

      // Dispose the auto-refreshing screen so its periodic bid poll is
      // cancelled before the widget test checks for pending timers.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );
}
