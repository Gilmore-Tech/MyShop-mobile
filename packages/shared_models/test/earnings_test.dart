import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

Map<String, dynamic> _summaryJson({
  Object? payoutCapability,
  Object? primaryAction,
  bool includePrimaryAction = false,
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
      if (includePrimaryAction) 'primaryAction': primaryAction,
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

  group('additive authoritative balance contract', () {
    Map<String, dynamic> detailedSummary({Object? primaryAction}) => {
          ..._summaryJson(
            includePrimaryAction: true,
            primaryAction: primaryAction,
          ),
          'availableBeforeDeductionsPesewas': 8000,
          'deductionsAppliedPesewas': 3000,
          'withdrawableBalancePesewas': 5000,
          'remainingDebtPesewas': 0,
          'heldBalancePesewas': 1200,
          'nextPayoutEligibleAt': '2026-08-15T12:30:00.000Z',
          'minimumWithdrawalPesewas': 1500,
        };

    test('parses complete balance and recognised withdrawal action', () {
      final summary = EarningsSummary.fromJson(
        detailedSummary(
          primaryAction: {
            'kind': 'request_withdrawal',
            'amountPesewas': 5000,
            'reasonCode': 'MANUAL_WITHDRAWAL_AVAILABLE',
          },
        ),
      );

      expect(summary.hasAuthoritativeBalanceBreakdown, isTrue);
      expect(summary.availableBeforeDeductionsPesewas, 8000);
      expect(summary.deductionsAppliedPesewas, 3000);
      expect(summary.withdrawableBalancePesewas, 5000);
      expect(summary.remainingDebtPesewas, 0);
      expect(summary.heldBalancePesewas, 1200);
      expect(summary.nextPayoutEligibleAt, DateTime.utc(2026, 8, 15, 12, 30));
      expect(summary.minimumWithdrawalPesewas, 1500);
      expect(summary.hasBalanceBreakdownContract, isTrue);
      expect(summary.hasValidCashCommissionOwedPesewas, isTrue);
      expect(summary.hasValidPendingPayoutsPesewas, isTrue);
      expect(summary.hasPrimaryActionContract, isTrue);
      expect(
        summary.primaryAction?.kind,
        EarningsPrimaryActionKind.requestWithdrawal,
      );
      expect(summary.primaryAction?.amountPesewas, 5000);
    });

    test('parses only sanitized reconciliation reason codes', () {
      final reversed = EarningsSummary.fromJson(
        detailedSummary(primaryAction: null)
          ..['reconciliationReasonCode'] = 'WITHDRAWAL_TRANSFER_REVERSED',
      );
      final unknown = EarningsSummary.fromJson(
        detailedSummary(primaryAction: null)
          ..['reconciliationReasonCode'] = 'raw gateway failure text',
      );

      expect(
        reversed.reconciliationReason,
        EarningsReconciliationReason.withdrawalTransferReversed,
      );
      expect(
        unknown.reconciliationReason,
        EarningsReconciliationReason.unknown,
      );
    });

    test(
      'absent primary action remains distinguishable for legacy fallback',
      () {
        final summary = EarningsSummary.fromJson(_summaryJson());

        expect(summary.hasPrimaryActionContract, isFalse);
        expect(summary.hasBalanceBreakdownContract, isFalse);
        expect(summary.primaryAction, isNull);
      },
    );

    test('explicit unknown or malformed action fails closed', () {
      for (final raw in <Object?>[
        {
          'kind': 'future_action',
          'amountPesewas': 5000,
          'reasonCode': 'FUTURE_REASON',
        },
        {
          'kind': 'request_withdrawal',
          'amountPesewas': '5000',
          'reasonCode': 'MANUAL_WITHDRAWAL_AVAILABLE',
        },
        null,
      ]) {
        final summary = EarningsSummary.fromJson(
          detailedSummary(primaryAction: raw),
        );
        expect(summary.hasPrimaryActionContract, isTrue);
        expect(
          summary.primaryAction?.kind,
          EarningsPrimaryActionKind.unsupported,
        );
      }
    });

    test(
      'partial or negative money contract cannot authorise a withdrawal',
      () {
        final json = detailedSummary(
          primaryAction: {
            'kind': 'request_withdrawal',
            'amountPesewas': 5000,
            'reasonCode': 'MANUAL_WITHDRAWAL_AVAILABLE',
          },
        )..['heldBalancePesewas'] = -1;
        final summary = EarningsSummary.fromJson(json);

        expect(summary.hasAuthoritativeBalanceBreakdown, isFalse);
        expect(summary.heldBalancePesewas, isNull);
      },
    );

    test('non-conserving balance breakdown fails closed', () {
      final json = detailedSummary(
        primaryAction: {
          'kind': 'request_withdrawal',
          'amountPesewas': 5000,
          'reasonCode': 'MANUAL_WITHDRAWAL_AVAILABLE',
        },
      )..['withdrawableBalancePesewas'] = 4999;
      final summary = EarningsSummary.fromJson(json);

      expect(summary.hasAuthoritativeBalanceBreakdown, isFalse);
    });

    test('withdrawable balance with remaining debt fails closed', () {
      final json = detailedSummary(
        primaryAction: {
          'kind': 'request_withdrawal',
          'amountPesewas': 5000,
          'reasonCode': 'MANUAL_WITHDRAWAL_AVAILABLE',
        },
      )..['remainingDebtPesewas'] = 1000;
      final summary = EarningsSummary.fromJson(json);

      expect(summary.hasAuthoritativeBalanceBreakdown, isFalse);
    });

    test('cash commission owed cannot exceed authoritative remaining debt', () {
      final json = detailedSummary(
        primaryAction: {
          'kind': 'request_withdrawal',
          'amountPesewas': 5000,
          'reasonCode': 'MANUAL_WITHDRAWAL_AVAILABLE',
        },
      )..['cashCommissionOwedPesewas'] = 1;
      final summary = EarningsSummary.fromJson(json);

      expect(summary.remainingDebtPesewas, 0);
      expect(summary.hasAuthoritativeBalanceBreakdown, isFalse);
    });

    test('cash debt and pending payout require exact JSON-safe integers', () {
      for (final field in <String>[
        'cashCommissionOwedPesewas',
        'pendingPayoutsPesewas',
      ]) {
        for (final raw in <Object?>[
          null,
          '0',
          0.0,
          0.5,
          -1,
          9007199254740992,
        ]) {
          final summary = EarningsSummary.fromJson(
            detailedSummary(primaryAction: null)..[field] = raw,
          );
          if (field == 'cashCommissionOwedPesewas') {
            expect(summary.hasValidCashCommissionOwedPesewas, isFalse);
          } else {
            expect(summary.hasValidPendingPayoutsPesewas, isFalse);
          }
          expect(summary.hasAuthoritativeBalanceBreakdown, isFalse);
        }
      }
    });

    test('present malformed additive key is not an old-backend response', () {
      final summary = EarningsSummary.fromJson({
        ..._summaryJson(
          payoutCapability: {
            'mode': 'manual_aggregate',
            'canRequest': true,
            'reasonCode': 'MANUAL_PAYOUT_AVAILABLE',
          },
        ),
        'withdrawableBalancePesewas': '5000',
      });

      expect(summary.hasPrimaryActionContract, isFalse);
      expect(summary.hasBalanceBreakdownContract, isTrue);
      expect(summary.withdrawableBalancePesewas, isNull);
      expect(summary.hasAuthoritativeBalanceBreakdown, isFalse);
    });

    test('minimum withdrawal parses only positive JSON-safe integers', () {
      for (final raw in <Object?>[null, 0, -1, '1500', 9007199254740992]) {
        final summary = EarningsSummary.fromJson(
          detailedSummary(primaryAction: null)
            ..['minimumWithdrawalPesewas'] = raw,
        );
        expect(summary.minimumWithdrawalPesewas, isNull);
      }
      expect(
        EarningsSummary.fromJson(
          detailedSummary(primaryAction: null),
        ).minimumWithdrawalPesewas,
        1500,
      );
    });

    test('money above the JSON safe-integer limit fails closed', () {
      final json = detailedSummary(primaryAction: null)
        ..['availableBeforeDeductionsPesewas'] = 9007199254740992;
      final summary = EarningsSummary.fromJson(json);

      expect(summary.availableBeforeDeductionsPesewas, isNull);
      expect(summary.hasAuthoritativeBalanceBreakdown, isFalse);
    });
  });
}
