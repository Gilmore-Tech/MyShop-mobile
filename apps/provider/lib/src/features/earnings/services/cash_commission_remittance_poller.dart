import 'package:api_client/api_client.dart';

typedef RemittanceStatusLoader = Future<CashCommissionRemittanceStatus>
    Function();
typedef RemittancePollDelay = Future<void> Function(Duration duration);

/// Bounded foreground monitor for a provider cash-commission payment.
///
/// The backend worker remains the durable authority if the sheet/app closes.
/// Transient network failures are deliberately retried because they are not
/// evidence that a MoMo charge failed.
class CashCommissionRemittancePoller {
  const CashCommissionRemittancePoller({
    this.interval = const Duration(seconds: 3),
    this.maxAttempts = 40,
    this.delay = Future<void>.delayed,
  });

  final Duration interval;
  final int maxAttempts;
  final RemittancePollDelay delay;

  Future<CashCommissionRemittanceStatus?> waitForTerminal(
    RemittanceStatusLoader load,
  ) async {
    for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
      if (attempt > 0) await delay(interval);
      try {
        final result = await load();
        if (result.isTerminal) return result;
      } catch (_) {
        // A transport/API failure is ambiguous. Keep the payment pending and
        // let the next poll (or the backend reconciliation worker) verify it.
      }
    }
    return null;
  }
}
