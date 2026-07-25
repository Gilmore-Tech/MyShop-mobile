import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

class ProviderReferralData {
  const ProviderReferralData({
    required this.code,
    required this.shareLink,
    required this.rewardPesewas,
    required this.totalReferrals,
    required this.pendingPesewas,
    required this.earnedPesewas,
  });

  final String code;
  final String? shareLink;
  final int rewardPesewas;
  final int totalReferrals;
  final int pendingPesewas;
  final int earnedPesewas;

  double get rewardGhs => rewardPesewas / 100;
  double get pendingGhs => pendingPesewas / 100;
  double get earnedGhs => earnedPesewas / 100;

  factory ProviderReferralData.fromJson(Map<String, dynamic> json) {
    return ProviderReferralData(
      code: json['code'] as String? ?? '',
      shareLink: json['shareLink'] as String?,
      rewardPesewas: (json['rewardPesewas'] as num?)?.toInt() ?? 0,
      totalReferrals: (json['totalReferrals'] as num?)?.toInt() ?? 0,
      pendingPesewas: (json['pendingPesewas'] as num?)?.toInt() ?? 0,
      earnedPesewas: (json['earnedPesewas'] as num?)?.toInt() ?? 0,
    );
  }
}

final providerReferralProvider =
    FutureProvider.autoDispose<ProviderReferralData>((ref) async {
  final json = await ref.read(userServiceProvider).getReferral();
  return ProviderReferralData.fromJson(json);
});
