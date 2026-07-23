import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myshop_client/src/core/di/providers.dart';
import 'package:myshop_client/src/features/ride/providers/ride_payment_provider.dart';
import 'package:myshop_client/src/features/services/data/pending_payment_store.dart';
import 'package:myshop_client/src/features/services/providers/payment_provider.dart';

void main() {
  const summary = PaymentSummary(
    jobId: 'job-1',
    serviceId: 'JOB-1',
    paymentRef: 'PAY-1',
    jobTitle: 'Repair socket',
    paymentDescription: 'Electrical repair',
    categoryName: 'Electrical',
    categoryIcon: Icons.bolt,
    location: 'Accra',
    completionLabel: 'Completed',
    artisanName: 'Ama Artisan',
    artisanFirstName: 'Ama',
    artisanAvatarColor: Colors.blue,
    serviceFeePesewas: 5000,
    materialsFeePesewas: 1000,
    totalPesewas: 6000,
    walletBalancePesewas: 0,
  );

  test('job payment never settles from a malformed completion response',
      () async {
    final notifier = PaymentNotifier(
      _FakePaymentService(
        initiateResponse: _acceptedPaymentResponse(
          message: 'raw provider account and gateway prose',
        ),
      ),
      _FakeJobService(
        confirmation: const {'jobId': 'job-1', 'status': 'pending_payment'},
        readBack: const {'jobId': 'job-1', 'status': 'pending_payment'},
      ),
      _MemoryPendingPaymentStore(),
    );
    addTearDown(notifier.dispose);

    await notifier.confirmPayment(
      jobId: 'job-1',
      summary: summary,
      momoPhone: '0240000000',
    );

    expect(notifier.state.phase, PaymentPhase.awaitingSettlement);
    expect(notifier.state.confirmation, isNull);
    expect(notifier.state.errorMessage, contains('couldn\'t confirm'));
    expect(notifier.state.displayText, isNot(contains('raw provider')));
  });

  test('job payment settles only after exact completed job authority',
      () async {
    final notifier = PaymentNotifier(
      _FakePaymentService(
        initiateResponse: _acceptedPaymentResponse(),
      ),
      _FakeJobService(
        confirmation: const {'jobId': 'job-1', 'status': 'completed'},
        readBack: const {'jobId': 'job-1', 'status': 'completed'},
      ),
      _MemoryPendingPaymentStore(),
    );
    addTearDown(notifier.dispose);

    await notifier.confirmPayment(
      jobId: 'job-1',
      summary: summary,
      momoPhone: '0240000000',
    );

    expect(notifier.state.phase, PaymentPhase.settled);
    expect(notifier.state.confirmation?.jobId, 'job-1');
    expect(notifier.state.confirmation?.transactionRef, 'payment-1');
  });

  test('ride gateway success waits for authoritative payment status', () async {
    final notifier = RidePaymentNotifier(
      _FakePaymentService(
        initiateResponse: _acceptedPaymentResponse(
          message: 'raw Paystack response must not reach the rider',
        ),
      ),
      _MemoryPendingPaymentStore(),
    );
    addTearDown(notifier.dispose);

    await notifier.initiate(
      rideId: 'ride-1',
      paymentMethod: 'momo_mtn',
      momoPhone: '0240000000',
    );
    await notifier.checkPaymentStatusNow();

    expect(notifier.state.phase, RidePaymentPhase.awaitingSettlement);
    expect(notifier.state.isSettled, isFalse);
    expect(notifier.state.displayText, isNot(contains('raw Paystack')));
  });

  test('job settlement refreshes coalesce while one status read is pending',
      () async {
    final paymentService = _ControlledPaymentService();
    final notifier = PaymentNotifier(
      paymentService,
      _FakeJobService(
        confirmation: const {'jobId': 'job-1', 'status': 'pending_payment'},
        readBack: const {'jobId': 'job-1', 'status': 'pending_payment'},
      ),
      _MemoryPendingPaymentStore(),
    );
    addTearDown(notifier.dispose);

    await notifier.confirmPayment(
      jobId: 'job-1',
      summary: summary,
      momoPhone: '0240000000',
    );
    final first = notifier.checkPaymentStatusNow(summary: summary);
    final second = notifier.checkPaymentStatusNow(summary: summary);
    await Future<void>.delayed(Duration.zero);

    expect(paymentService.statusCalls, 1);

    paymentService.statusResponse.complete(const {'status': 'pending'});
    await Future.wait([first, second]);
  });

  test('ride settlement refreshes coalesce while one status read is pending',
      () async {
    final paymentService = _ControlledPaymentService();
    final notifier = RidePaymentNotifier(
      paymentService,
      _MemoryPendingPaymentStore(),
    );
    addTearDown(notifier.dispose);

    await notifier.initiate(
      rideId: 'ride-1',
      paymentMethod: 'momo_mtn',
      momoPhone: '0240000000',
    );
    final first = notifier.checkPaymentStatusNow();
    final second = notifier.checkPaymentStatusNow();
    await Future<void>.delayed(Duration.zero);

    expect(paymentService.statusCalls, 1);

    paymentService.statusResponse.complete(const {'status': 'pending'});
    await Future.wait([first, second]);
  });

  test('late job status from an older payment attempt cannot settle the retry',
      () async {
    final paymentService = _SequencedPaymentService();
    final notifier = PaymentNotifier(
      paymentService,
      _FakeJobService(
        confirmation: const {'jobId': 'job-1', 'status': 'pending_payment'},
        readBack: const {'jobId': 'job-1', 'status': 'pending_payment'},
      ),
      _MemoryPendingPaymentStore(),
    );
    addTearDown(notifier.dispose);

    await notifier.confirmPayment(
      jobId: 'job-1',
      summary: summary,
      momoPhone: '0240000000',
    );
    final oldRead = notifier.checkPaymentStatusNow(summary: summary);
    await Future<void>.delayed(Duration.zero);

    notifier.resetForRetry();
    await notifier.confirmPayment(
      jobId: 'job-1',
      summary: summary,
      momoPhone: '0240000000',
      isRetry: true,
    );
    final currentRead = notifier.checkPaymentStatusNow(summary: summary);
    await Future<void>.delayed(Duration.zero);

    paymentService.statusResponses[0].complete(const {'status': 'success'});
    await oldRead;

    expect(notifier.state.paymentId, 'payment-2');
    expect(notifier.state.phase, PaymentPhase.awaitingSettlement);

    paymentService.statusResponses[1].complete(const {'status': 'pending'});
    await currentRead;
  });

  test('late ride status from an older payment attempt cannot settle the retry',
      () async {
    final paymentService = _SequencedPaymentService();
    final notifier = RidePaymentNotifier(
      paymentService,
      _MemoryPendingPaymentStore(),
    );
    addTearDown(notifier.dispose);

    await notifier.initiate(
      rideId: 'ride-1',
      paymentMethod: 'momo_mtn',
      momoPhone: '0240000000',
    );
    final oldRead = notifier.checkPaymentStatusNow();
    await Future<void>.delayed(Duration.zero);

    notifier.resetForRetry();
    await notifier.initiate(
      rideId: 'ride-1',
      paymentMethod: 'momo_mtn',
      momoPhone: '0240000000',
      isRetry: true,
    );
    final currentRead = notifier.checkPaymentStatusNow();
    await Future<void>.delayed(Duration.zero);

    paymentService.statusResponses[0].complete(const {'status': 'success'});
    await oldRead;

    expect(notifier.state.paymentId, 'payment-2');
    expect(notifier.state.phase, RidePaymentPhase.awaitingSettlement);

    paymentService.statusResponses[1].complete(const {'status': 'pending'});
    await currentRead;
  });

  test('payment providers emit privacy-safe lifecycle telemetry', () async {
    final telemetry = _RecordingTelemetry();
    final paymentService = _FakePaymentService(
      initiateResponse: _acceptedPaymentResponse(),
    );
    final store = _MemoryPendingPaymentStore();
    final container = ProviderContainer(
      overrides: [
        systemTelemetryProvider.overrideWithValue(telemetry),
        paymentServiceProvider.overrideWithValue(paymentService),
        jobServiceProvider.overrideWithValue(
          _FakeJobService(
            confirmation: const {'jobId': 'job-1', 'status': 'completed'},
            readBack: const {'jobId': 'job-1', 'status': 'completed'},
          ),
        ),
        pendingPaymentStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);

    await container.read(paymentNotifierProvider.notifier).confirmPayment(
          jobId: 'job-1',
          summary: summary,
          momoPhone: '0240000000',
        );
    await container.read(ridePaymentNotifierProvider.notifier).initiate(
          rideId: 'ride-1',
          paymentMethod: 'momo_mtn',
          momoPhone: '0240000000',
        );

    expect(
      telemetry.events,
      containsAll(<String>[
        'artisan_payment_processing:success',
        'artisan_payment_settled:success',
        'ride_payment_processing:success',
        'ride_payment_awaitingSettlement:success',
      ]),
    );
    final recorded = telemetry.events.join(' ');
    expect(recorded, isNot(contains('0240000000')));
    expect(recorded, isNot(contains('payment-1')));
    expect(recorded, isNot(contains('paystack-reference-1')));
  });
}

Map<String, dynamic> _acceptedPaymentResponse({String? message}) => {
      'paymentId': 'payment-1',
      'reference': 'paystack-reference-1',
      'data': {
        'status': 'success',
        if (message != null) 'message': message,
      },
    };

class _FakePaymentService extends PaymentService {
  _FakePaymentService({required this.initiateResponse}) : super(Dio());

  final Map<String, dynamic> initiateResponse;

  @override
  Future<Map<String, dynamic>> initiatePayment({
    required String bookingType,
    required String bookingId,
    required String paymentMethod,
    String? momoPhone,
    String? cardToken,
    String? promoCode,
  }) async =>
      initiateResponse;

  @override
  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) async =>
      const {'status': 'pending'};
}

class _ControlledPaymentService extends _FakePaymentService {
  _ControlledPaymentService()
      : super(
          initiateResponse: {
            'paymentId': 'payment-1',
            'reference': 'paystack-reference-1',
            'data': {'status': 'pending'},
          },
        );

  final statusResponse = Completer<Map<String, dynamic>>();
  int statusCalls = 0;

  @override
  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) {
    statusCalls += 1;
    return statusResponse.future;
  }
}

class _SequencedPaymentService extends PaymentService {
  _SequencedPaymentService() : super(Dio());

  final statusResponses = [
    Completer<Map<String, dynamic>>(),
    Completer<Map<String, dynamic>>(),
  ];
  int initiateCalls = 0;
  int statusCalls = 0;

  @override
  Future<Map<String, dynamic>> initiatePayment({
    required String bookingType,
    required String bookingId,
    required String paymentMethod,
    String? momoPhone,
    String? cardToken,
    String? promoCode,
  }) async {
    initiateCalls += 1;
    return {
      'paymentId': 'payment-$initiateCalls',
      'reference': 'reference-$initiateCalls',
      'data': {'status': 'pending'},
    };
  }

  @override
  Future<Map<String, dynamic>> getPaymentStatus(String paymentId) {
    final index = statusCalls;
    statusCalls += 1;
    return statusResponses[index].future;
  }

  @override
  Future<Map<String, dynamic>> abandonByBooking({
    required String bookingType,
    required String bookingId,
  }) async =>
      const {'status': 'abandoned'};
}

class _RecordingTelemetry extends SystemTelemetryService {
  _RecordingTelemetry()
      : super(
          dio: Dio(),
          deviceIdProvider: DeviceIdProvider(SecureTokenStorage()),
          app: 'client',
        );

  final List<String> events = [];

  @override
  void trackAction(
    String action, {
    String outcome = 'success',
    String? correlationId,
    Map<String, Object?> metadata = const {},
  }) {
    events.add('$action:$outcome');
  }
}

class _FakeJobService extends JobService {
  _FakeJobService({required this.confirmation, required this.readBack})
      : super(Dio());

  final Map<String, dynamic> confirmation;
  final Map<String, dynamic> readBack;

  @override
  Future<Map<String, dynamic>> confirmJobCompletion(String jobId) async =>
      confirmation;

  @override
  Future<Map<String, dynamic>> getJob(String jobId) async => readBack;
}

class _MemoryPendingPaymentStore extends PendingPaymentStore {
  final Map<String, PendingPaymentRecord> records = {};

  @override
  Future<void> save(PendingPaymentRecord record) async {
    records['${record.bookingType}:${record.bookingId}'] = record;
  }

  @override
  Future<void> clear({
    required String bookingType,
    required String bookingId,
  }) async {
    records.remove('$bookingType:$bookingId');
  }
}
