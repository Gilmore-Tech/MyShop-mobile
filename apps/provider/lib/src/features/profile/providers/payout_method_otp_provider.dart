import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../data/payout_method_otp_service.dart';

/// Backed by the app's Dio client. The service is stateless — the OTP
/// candidate lives server-side (Redis), keyed by the authenticated user.
final payoutMethodOtpServiceProvider = Provider<PayoutMethodOtpService>((ref) {
  return PayoutMethodOtpService(ref.watch(dioProvider));
});
