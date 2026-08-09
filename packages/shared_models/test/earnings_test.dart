import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

Map<String, dynamic> _summaryJson({
  Object? payoutCapability,
  int availablePesewas = 8000,
  int owedPesewas = 0,
}) =>
    {
      'role': 'driver',
      'period': 'week',
      'availableBalancePesewas': availablePesewas,
      'todayAvailableBalancePesewas': 8000,
      'weeklyAvailableBalancePesewas': 8000,
      'netEarningsPesewas': 8000,
      'tipsEarnedPesewas': 0,
      'paidOutPesewas': 0,
      'cashCommissionOwedPesewas': owedPesewas,
      'pendingPayoutsPesewas': 0,
      'series': <dynamic>[],
      'granularity': 'day',
      if (payoutCapability != null) 'payoutCapability': payoutCapability,
    };

void main() {
  group('PayoutCapability', () {
    test('parses explicit manual request authority', () {
      final summary = EarningsSummary.fromJson(
        _summaryJson(
          payoutCapability: {
            'mode': 'manual_aggregate',
            'canRequest': true,
            'reasonCode': 'MANUAL_PAYOUT_AVAILABLE',
          },
        ),
      );

      expect(
        summary.payoutCapability.mode,
        PayoutCapabilityMode.manualAggregate,
      );
      expect(summary.payoutCapability.canRequest, isTrue);
      expect(
        summary.payoutCapability.reason,
        PayoutCapabilityReason.manualPayoutAvailable,
      );
    });

    test('parses automatic exact as non-requestable', () {
      final summary = EarningsSummary.fromJson(
        _summaryJson(
          payoutCapability: {
            'mode': 'automatic_exact',
            'canRequest': true,
            'reasonCode': 'AUTOMATIC_PAYOUT_ACTIVE',
          },
        ),
      );

      expect(
        summary.payoutCapability.mode,
        PayoutCapabilityMode.automaticExact,
      );
      expect(summary.payoutCapability.canRequest, isFalse);
    });

    test('missing capability fails closed for older backends', () {
      final summary = EarningsSummary.fromJson(_summaryJson());

      expect(summary.payoutCapability.mode, PayoutCapabilityMode.unavailable);
      expect(summary.payoutCapability.canRequest, isFalse);
    });

    test('unknown mode and reason fail closed', () {
      final summary = EarningsSummary.fromJson(
        _summaryJson(
          payoutCapability: {
            'mode': 'future_money_rail',
            'canRequest': true,
            'reasonCode': 'FUTURE_REASON',
          },
        ),
      );

      expect(summary.payoutCapability.mode, PayoutCapabilityMode.unavailable);
      expect(summary.payoutCapability.reason, PayoutCapabilityReason.unknown);
      expect(summary.payoutCapability.canRequest, isFalse);
    });

    test('malformed field types and non-map payloads fail closed', () {
      for (final raw in <Object?>[
        <String, dynamic>{
          'mode': 7,
          'canRequest': 'true',
          'reasonCode': <String>['MANUAL_PAYOUT_AVAILABLE'],
        },
        <Object?>['manual_aggregate', true],
        42,
      ]) {
        final capability = PayoutCapability.fromJson(raw);
        expect(capability.mode, PayoutCapabilityMode.unavailable);
        expect(capability.reason, PayoutCapabilityReason.unknown);
        expect(capability.canRequest, isFalse);
      }
    });

    test('manual mode without matching reason remains fail closed', () {
      final capability = PayoutCapability.fromJson({
        'mode': 'manual_aggregate',
        'canRequest': true,
        'reasonCode': 'PAYOUT_RAIL_UNAVAILABLE',
      });

      expect(capability.mode, PayoutCapabilityMode.manualAggregate);
      expect(capability.canRequest, isFalse);
    });
  });

  group('provider earnings authority', () {
    test('headline shows full durable debt without inferring an offset', () {
      final summary = EarningsSummary.fromJson(
        _summaryJson(availablePesewas: 8000, owedPesewas: 5000),
      );

      expect(summary.effectiveBalancePesewas, 3000);
      expect(summary.headlineBalancePesewas, -5000);
      expect(summary.isInArrears, isTrue);
    });

    test('today take-home trusts promo and relief aware net', () {
      const card = EarningsTodayCard(
        role: EarningsRole.driver,
        date: '2026-08-09',
        bookingsCount: 1,
        hoursWorkedMinutes: 20,
        tipsEarnedPesewas: 0,
        grossEarningsPesewas: 10000,
        commissionPesewas: 1000,
        netEarningsPesewas: 9000,
      );

      // A local fixed-rate reconstruction could produce 8000. The server's
      // commission-relief-aware provider earning must remain authoritative.
      expect(card.effectiveEarningsPesewas, 9000);
    });

    test('report take-home trusts mixed cash and in-app authoritative net', () {
      const report = EarningsReport(
        role: EarningsRole.artisan,
        startDate: null,
        endDate: null,
        granularity: EarningsGranularity.day,
        grossEarningsPesewas: 20000,
        netEarningsPesewas: 18000,
        commissionChargedPesewas: 2000,
        tipsEarnedPesewas: 0,
        bookingsCompleted: 2,
        averageFarePesewas: 10000,
        hoursWorkedMinutes: 90,
        trendPct: null,
        series: <EarningsReportPoint>[],
      );

      expect(report.effectiveEarningsPesewas, 18000);
    });
  });
}
