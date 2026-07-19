import 'package:api_client/api_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
