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
  });
}
