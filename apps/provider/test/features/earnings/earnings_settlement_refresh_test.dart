import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/core/services/fcm_service.dart';
import 'package:myshop_provider/src/core/services/local_notification_service.dart';
import 'package:myshop_provider/src/features/earnings/data/earnings_service.dart';
import 'package:myshop_provider/src/features/earnings/providers/earnings_providers.dart';
import 'package:shared_models/shared_models.dart';

class _CountingEarningsService extends EarningsService {
  _CountingEarningsService() : super(Dio());

  int todayReads = 0;
  int summaryReads = 0;
  int reportReads = 0;
  int payoutReads = 0;

  @override
  Future<EarningsTodayCard> getTodayCard({required EarningsRole role}) async {
    todayReads += 1;
    return EarningsTodayCard.empty(role);
  }

  @override
  Future<EarningsSummary> getSummary({
    required EarningsRole role,
    required EarningsPeriod period,
  }) async {
    summaryReads += 1;
    return _summary(role: role, period: period);
  }

  @override
  Future<EarningsReport> getReport(EarningsReportQuery query) async {
    reportReads += 1;
    return EarningsReport.empty(query.role);
  }

  @override
  Future<List<DriverPayout>> getPayouts() async {
    payoutReads += 1;
    return const <DriverPayout>[];
  }
}

EarningsSummary _summary({
  EarningsRole role = EarningsRole.driver,
  EarningsPeriod period = EarningsPeriod.week,
  int availablePesewas = 5000,
  int pendingPesewas = 0,
  int cashCommissionOwedPesewas = 0,
  PayoutCapability payoutCapability = const PayoutCapability(
    mode: PayoutCapabilityMode.manualAggregate,
    canRequest: true,
    reason: PayoutCapabilityReason.manualPayoutAvailable,
    rawReasonCode: 'MANUAL_PAYOUT_AVAILABLE',
  ),
}) {
  return EarningsSummary(
    role: role,
    period: period,
    startDate: null,
    endDate: null,
    availableBalancePesewas: availablePesewas,
    todayAvailableBalancePesewas: 1200,
    weeklyAvailableBalancePesewas: 4800,
    netEarningsPesewas: 4800,
    tipsEarnedPesewas: 0,
    paidOutPesewas: 0,
    cashCommissionOwedPesewas: cashCommissionOwedPesewas,
    pendingPayoutsPesewas: pendingPesewas,
    series: const <EarningsSummaryPoint>[],
    granularity: EarningsGranularity.day,
    payoutCapability: payoutCapability,
  );
}

void main() {
  test('only payout-authoritative notifications refresh earnings', () {
    expect(
      isEarningsSettlementNotification(
        NotificationPayload.typePaymentReceived,
      ),
      isTrue,
    );
    expect(
      isEarningsSettlementNotification(NotificationPayload.typeEarningsUpdated),
      isTrue,
    );
    expect(
      isEarningsSettlementNotification(NotificationPayload.typeRideSettled),
      isTrue,
    );
    expect(
      isEarningsSettlementNotification(
        NotificationPayload.typeJobPaymentReleasing,
      ),
      isTrue,
    );
    expect(
      isEarningsSettlementNotification(
        NotificationPayload.typeJobConfirmedComplete,
      ),
      isTrue,
    );
    expect(
      isEarningsSettlementNotification(NotificationPayload.typeRideRequest),
      isFalse,
    );
  });

  test('settlement cache bust refreshes every earnings API surface', () async {
    final service = _CountingEarningsService();
    final container = ProviderContainer(
      overrides: [earningsServiceProvider.overrideWithValue(service)],
    );
    addTearDown(container.dispose);

    const role = EarningsRole.driver;
    const summaryKey = EarningsSummaryKey(
      role: role,
      period: EarningsPeriod.week,
    );
    const reportQuery = EarningsReportQuery.preset(
      role: role,
      period: EarningsPeriod.week,
    );

    Future<void> readAll() async {
      await Future.wait<Object?>([
        container.read(todayCardProvider(role).future),
        container.read(earningsSummaryProvider(summaryKey).future),
        container.read(earningsReportProvider(reportQuery).future),
        container.read(payoutsProvider.future),
      ]);
    }

    await readAll();
    expect(
      [
        service.todayReads,
        service.summaryReads,
        service.reportReads,
        service.payoutReads,
      ],
      [1, 1, 1, 1],
    );

    container.read(invalidateEarningsCachesProvider)();
    await readAll();

    expect(
      [
        service.todayReads,
        service.summaryReads,
        service.reportReads,
        service.payoutReads,
      ],
      [2, 2, 2, 2],
    );
  });

  test(
    'settlement refresh wave is finite and duplicate waves are replaced',
    () async {
      final service = _CountingEarningsService();
      final container = ProviderContainer(
        overrides: [
          earningsServiceProvider.overrideWithValue(service),
          earningsSettlementRetryDelaysProvider.overrideWithValue(const [
            Duration(milliseconds: 2),
            Duration(milliseconds: 4),
            Duration(milliseconds: 6),
          ]),
        ],
      );
      addTearDown(container.dispose);

      const key = EarningsSummaryKey(
        role: EarningsRole.driver,
        period: EarningsPeriod.week,
      );
      final subscription = container.listen(
        earningsSummaryProvider(key),
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);
      await container.read(earningsSummaryProvider(key).future);

      final coordinator = container.read(earningsRefreshCoordinatorProvider);
      coordinator.scheduleAfterSettlement();
      coordinator.scheduleAfterSettlement();
      expect(coordinator.pendingRetryCount, 3);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(coordinator.pendingRetryCount, 0);
      expect(
        service.summaryReads,
        lessThanOrEqualTo(6),
        reason: 'duplicate signals must not create two independent retry waves',
      );
    },
  );

  test('payout CTA is fenced while an authoritative summary refreshes', () {
    final historicalSummary = _summary();

    expect(
      canRequestPayoutFromSummary(
        summary: historicalSummary,
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isTrue,
    );
    expect(
      canRequestPayoutFromSummary(
        summary: historicalSummary,
        summaryRefreshing: true,
        summaryHasError: false,
      ),
      isFalse,
    );
    expect(historicalSummary.todayAvailableBalancePesewas, 1200);
    expect(historicalSummary.weeklyAvailableBalancePesewas, 4800);
  });

  test('legacy payout authority also enforces the frozen GHS15 minimum', () {
    expect(
      canRequestPayoutFromSummary(
        summary: _summary(availablePesewas: 1499),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isFalse,
    );
    expect(
      canRequestPayoutFromSummary(
        summary: _summary(availablePesewas: 1500),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isTrue,
    );
  });

  test('pending settlement, debt, errors and zero balance fence payout', () {
    expect(
      canRequestPayoutFromSummary(
        summary: _summary(pendingPesewas: 5000),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isFalse,
    );
    expect(
      canRequestPayoutFromSummary(
        summary: _summary(cashCommissionOwedPesewas: 6000),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isFalse,
    );
    expect(
      canRequestPayoutFromSummary(
        summary: _summary(cashCommissionOwedPesewas: 1000),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isFalse,
      reason: 'available funds must not be assumed to offset durable debt',
    );
    expect(
      canRequestPayoutFromSummary(
        summary: _summary(availablePesewas: 0),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isFalse,
    );
    expect(
      canRequestPayoutFromSummary(
        summary: _summary(),
        summaryRefreshing: false,
        summaryHasError: true,
      ),
      isFalse,
    );
    expect(
      canRequestPayoutFromSummary(
        summary: _summary(
          payoutCapability: const PayoutCapability.unavailable(),
        ),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isFalse,
      reason: 'an older response without capability must fail closed',
    );
  });

  test('new withdrawal authority is accepted only when amounts agree', () {
    EarningsSummary detailed({
      int actionAmount = 5000,
      int minimumWithdrawalPesewas = 1500,
    }) =>
        EarningsSummary.fromJson({
          'role': 'driver',
          'period': 'week',
          'availableBalancePesewas': 5000,
          'todayAvailableBalancePesewas': 0,
          'weeklyAvailableBalancePesewas': 0,
          'netEarningsPesewas': 0,
          'tipsEarnedPesewas': 0,
          'paidOutPesewas': 0,
          'cashCommissionOwedPesewas': 0,
          'pendingPayoutsPesewas': 0,
          'availableBeforeDeductionsPesewas': 6000,
          'deductionsAppliedPesewas': 1000,
          'withdrawableBalancePesewas': 5000,
          'remainingDebtPesewas': 0,
          'heldBalancePesewas': 0,
          'minimumWithdrawalPesewas': minimumWithdrawalPesewas,
          'primaryAction': {
            'kind': 'request_withdrawal',
            'amountPesewas': actionAmount,
            'reasonCode': 'MANUAL_WITHDRAWAL_AVAILABLE',
          },
          'series': <dynamic>[],
          'granularity': 'day',
        });

    expect(
      canRequestPayoutFromSummary(
        summary: detailed(),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isTrue,
    );
    expect(
      canRequestPayoutFromSummary(
        summary: detailed(actionAmount: 4999),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isFalse,
    );
    expect(
      canRequestPayoutFromSummary(
        summary: detailed(minimumWithdrawalPesewas: 1400),
        summaryRefreshing: false,
        summaryHasError: false,
      ),
      isFalse,
      reason: 'the new contract must use the frozen GHS15 minimum',
    );
  });
}
