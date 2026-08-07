import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// A promotional campaign currently active for the signed-in client.
///
/// Served by `GET /v1/promos/active`. All parsing is null-safe and
/// tolerant of missing keys (additive contract — an older backend that
/// omits a field must not break the client). Unknown fields are ignored.
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
    );
  }

  static DateTime? _parseDate(dynamic value) =>
      value is String ? DateTime.tryParse(value) : null;

  final String id;
  final String name;
  final String description;
  final String termsText;

  /// `percentage_discount` | `fixed_discount`.
  final String campaignType;

  /// Percentage points for `percentage_discount` (e.g. 15 = 15% off);
  /// pesewas for `fixed_discount` (e.g. 500 = GHS 5 off).
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

  bool get isPercentage => campaignType == 'percentage_discount';
  bool get hasBanner => bannerUrl != null && bannerUrl!.trim().isNotEmpty;
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
