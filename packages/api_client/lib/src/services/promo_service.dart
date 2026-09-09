import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// A promotional campaign currently active for the signed-in user.
///
/// Served by `GET /v1/promos/active`. The backend filters campaigns by
/// the caller's token role: clients receive discount campaigns, while
/// drivers/artisans receive their role's incentive campaigns and progress.
/// All parsing is null-safe and tolerant of missing keys (additive
/// contract — an older backend that omits a field must not break the
/// client). Unknown fields are ignored.
class ActivePromoCampaign {
  const ActivePromoCampaign({
    required this.id,
    required this.name,
    this.description = '',
    this.termsText = '',
    this.campaignType = '',
    this.discountValue = 0,
    this.maxDiscountPesewas,
    this.minBookingPesewas,
    this.promoScope = '',
    this.newClientsOnly = false,
    this.startsAt,
    this.endsAt,
    this.bannerUrl,
    this.bannerPriority = 0,
    this.audience = 'client',
    this.providerPromo,
  });

  factory ActivePromoCampaign.fromJson(Map<String, dynamic> json) {
    return ActivePromoCampaign(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      termsText: json['termsText'] as String? ?? '',
      campaignType: json['campaignType'] as String? ?? '',
      discountValue: json['discountValue'] as num? ?? 0,
      maxDiscountPesewas: (json['maxDiscountPesewas'] as num?)?.toInt(),
      minBookingPesewas: (json['minBookingPesewas'] as num?)?.toInt(),
      promoScope: json['promoScope'] as String? ?? '',
      newClientsOnly: json['newClientsOnly'] as bool? ?? false,
      startsAt: _parseDate(json['startsAt']),
      endsAt: _parseDate(json['endsAt']),
      bannerUrl: json['bannerUrl'] as String?,
      bannerPriority: (json['bannerPriority'] as num?)?.toInt() ?? 0,
      audience: json['audience'] as String? ?? 'client',
      providerPromo: json['providerPromo'] is Map<String, dynamic>
          ? ProviderPromoProgress.fromJson(
              json['providerPromo'] as Map<String, dynamic>,
            )
          : null,
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  final String id;
  final String name;
  final String description;
  final String termsText;

  /// `percentage_discount` | `fixed_discount` | `commission_relief`.
  final String campaignType;

  /// Percentage points for `percentage_discount` (e.g. 15 = 15% off);
  /// pesewas for `fixed_discount` (e.g. 500 = GHS 5 off); percent of the
  /// platform commission forgiven (1-100) for `commission_relief`.
  final num discountValue;

  final int? maxDiscountPesewas;
  final int? minBookingPesewas;

  /// `ride` | `artisan_job` | `both`.
  final String promoScope;

  final bool newClientsOnly;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// Nullable — campaigns without a banner never appear in the carousel.
  final String? bannerUrl;

  final int bannerPriority;

  /// Who the campaign targets: `client` (default), `driver`, or `artisan`.
  /// Legacy provider builds may also return `provider_driver` or
  /// `provider_artisan`. Older backends omit the field entirely —
  /// those campaigns were always client-audience, hence the default.
  final String audience;

  /// Present only for the new provider-incentive contract. Its absence keeps
  /// older backends and client campaigns fully compatible.
  final ProviderPromoProgress? providerPromo;

  bool get isPercentage => campaignType == 'percentage_discount';
  bool get isCommissionRelief => campaignType == 'commission_relief';
  bool get hasBanner => bannerUrl != null && bannerUrl!.trim().isNotEmpty;

  num? get commissionReliefPercent =>
      providerPromo?.rewardKind == 'commission_relief'
      ? providerPromo!.rewardValue
      : isCommissionRelief && providerPromo == null
      ? discountValue
      : null;
}

/// Server-authoritative progress for one provider incentive campaign.
/// Selected targets are AND-combined: every non-null target must be met.
class ProviderPromoProgress {
  const ProviderPromoProgress({
    required this.rewardKind,
    required this.rewardValue,
    this.completedBookingsTarget,
    this.verifiedOnlineMinutesTarget,
    this.generatedRevenueTargetPesewas,
    this.completedBookings = 0,
    this.verifiedOnlineSeconds = 0,
    this.generatedRevenuePesewas = 0,
    this.qualifyingCommissionPesewas = 0,
    this.qualifyingEarningsPesewas = 0,
    this.qualified = false,
    this.qualifiedAt,
    this.calculatedRewardPesewas = 0,
    this.settlementStatus = 'pending',
    this.grossRewardPesewas,
    this.deductionsAppliedPesewas,
    this.withdrawableRewardPesewas,
  });

  factory ProviderPromoProgress.fromJson(Map<String, dynamic> json) {
    int? intOrNull(String key) => (json[key] as num?)?.toInt();
    int intOrZero(String key) => intOrNull(key) ?? 0;

    return ProviderPromoProgress(
      rewardKind: json['rewardKind'] as String? ?? '',
      rewardValue: intOrZero('rewardValue'),
      completedBookingsTarget: intOrNull('completedBookingsTarget'),
      verifiedOnlineMinutesTarget: intOrNull('verifiedOnlineMinutesTarget'),
      generatedRevenueTargetPesewas: intOrNull('generatedRevenueTargetPesewas'),
      completedBookings: intOrZero('completedBookings'),
      verifiedOnlineSeconds: intOrZero('verifiedOnlineSeconds'),
      generatedRevenuePesewas: intOrZero('generatedRevenuePesewas'),
      qualifyingCommissionPesewas: intOrZero('qualifyingCommissionPesewas'),
      qualifyingEarningsPesewas: intOrZero('qualifyingEarningsPesewas'),
      qualified: json['qualified'] as bool? ?? false,
      qualifiedAt: ActivePromoCampaign._parseDate(json['qualifiedAt']),
      calculatedRewardPesewas: intOrZero('calculatedRewardPesewas'),
      settlementStatus: json['settlementStatus'] as String? ?? 'pending',
      grossRewardPesewas: intOrNull('grossRewardPesewas'),
      deductionsAppliedPesewas: intOrNull('deductionsAppliedPesewas'),
      withdrawableRewardPesewas: intOrNull('withdrawableRewardPesewas'),
    );
  }

  final String rewardKind;
  final int rewardValue;
  final int? completedBookingsTarget;
  final int? verifiedOnlineMinutesTarget;
  final int? generatedRevenueTargetPesewas;
  final int completedBookings;
  final int verifiedOnlineSeconds;
  final int generatedRevenuePesewas;
  final int qualifyingCommissionPesewas;
  final int qualifyingEarningsPesewas;
  final bool qualified;
  final DateTime? qualifiedAt;
  final int calculatedRewardPesewas;
  final String settlementStatus;
  final int? grossRewardPesewas;
  final int? deductionsAppliedPesewas;
  final int? withdrawableRewardPesewas;

  bool get isFixedBonus => rewardKind == 'fixed_bonus';
  bool get isCommissionRelief => rewardKind == 'commission_relief';
  bool get isGuaranteedEarnings => rewardKind == 'guaranteed_earnings';

  bool get bookingsComplete =>
      completedBookingsTarget == null ||
      completedBookings >= completedBookingsTarget!;
  bool get onlineTimeComplete =>
      verifiedOnlineMinutesTarget == null ||
      verifiedOnlineSeconds >= verifiedOnlineMinutesTarget! * 60;
  bool get revenueComplete =>
      generatedRevenueTargetPesewas == null ||
      generatedRevenuePesewas >= generatedRevenueTargetPesewas!;

  double get overallProgress {
    final ratios = <double>[
      if (completedBookingsTarget != null)
        completedBookings / completedBookingsTarget!,
      if (verifiedOnlineMinutesTarget != null)
        verifiedOnlineSeconds / (verifiedOnlineMinutesTarget! * 60),
      if (generatedRevenueTargetPesewas != null)
        generatedRevenuePesewas / generatedRevenueTargetPesewas!,
    ];
    if (ratios.isEmpty) return 0;
    final total = ratios.fold<double>(
      0,
      (sum, value) => sum + value.clamp(0, 1).toDouble(),
    );
    return total / ratios.length;
  }
}

/// Service for promotional-campaign endpoints.
class PromoService {
  PromoService(this._dio);
  final Dio _dio;

  dynamic _unwrap(Response response) {
    final body = response.data as Map<String, dynamic>;
    if (body['success'] == true) return body['data'];
    throw ApiException.fromDioException(
      DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      ),
    );
  }

  /// GET /promos/active — campaigns currently visible to this client.
  ///
  /// Returns an empty list when the feature is off (backend serves
  /// `{ campaigns: [] }`) or when the payload shape is unrecognised —
  /// the promo surface must render nothing rather than error.
  Future<List<ActivePromoCampaign>> getActiveCampaigns() async {
    try {
      final response = await _dio.get('/promos/active');
      final data = _unwrap(response);
      final campaigns = data is Map<String, dynamic> ? data['campaigns'] : null;
      if (campaigns is! List) return const [];
      return campaigns
          .whereType<Map<String, dynamic>>()
          .map(ActivePromoCampaign.fromJson)
          .where((c) => c.id.isNotEmpty && c.name.isNotEmpty)
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
