import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop_provider/src/features/earnings/services/cash_commission_remittance_poller.dart';

CashCommissionRemittanceStatus _status(
  String status, {
  String? gatewayStatus,
  int owedPesewas = 1000,
}) {
  return CashCommissionRemittanceStatus(
    remitId: 'remit-1',
    status: status,
    gatewayStatus: gatewayStatus,
    amountPesewas: 500,
    owedPesewas: owedPesewas,
  );
}

void main() {
  const noDelay = Duration.zero;

  test('returns the first completed authoritative status', () async {
    var calls = 0;
    final poller = CashCommissionRemittancePoller(
      interval: noDelay,
      maxAttempts: 4,
      delay: (_) async {},
    );

    final result = await poller.waitForTerminal(() async {
      calls += 1;
      return calls < 3
          ? _status('processing', gatewayStatus: 'ongoing')
          : _status('completed', gatewayStatus: 'success', owedPesewas: 500);
    });

    expect(calls, 3);
    expect(result?.isCompleted, isTrue);
    expect(result?.owedPesewas, 500);
  });

  test(
    'returns terminal failure without changing the supplied owing amount',
    () async {
      final poller = CashCommissionRemittancePoller(
        interval: noDelay,
        maxAttempts: 2,
        delay: (_) async {},
      );

      final result = await poller.waitForTerminal(
        () async =>
            _status('failed', gatewayStatus: 'abandoned', owedPesewas: 1000),
      );

      expect(result?.isFailed, isTrue);
      expect(result?.gatewayStatus, 'abandoned');
      expect(result?.owedPesewas, 1000);
    },
  );

  test(
    'retries transient errors and times out without inventing success',
    () async {
      var calls = 0;
      final poller = CashCommissionRemittancePoller(
        interval: noDelay,
        maxAttempts: 3,
        delay: (_) async {},
      );

      final result = await poller.waitForTerminal(() async {
        calls += 1;
        if (calls == 1) throw Exception('temporary network failure');
        return _status('processing', gatewayStatus: 'pending');
      });

      expect(calls, 3);
      expect(result, isNull);
    },
  );
}
