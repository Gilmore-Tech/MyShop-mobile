/// Positive, server-authored ride access charge.
///
/// The canonical wire shape is:
/// `toll: {label, amountPesewas, applicationMode?}`. During the rollout,
/// [fromRideJson] also accepts the flat `tollFeePesewas` alias. Callers should
/// only render a row when this parser returns a value; a zero amount is the
/// same as no charge and deliberately carries no display label.
class RideToll {
  const RideToll({
    required this.label,
    required this.amountPesewas,
    this.applicationMode,
  });

  factory RideToll.fromJson(Map<String, dynamic> json) {
    final amount = _positiveMoney(
      json['amountPesewas'] ?? json['tollFeePesewas'],
    );
    if (amount == null) {
      throw const FormatException('Ride toll amount must be positive');
    }
    return RideToll(
      label: _displayLabel(json['label'] ?? json['tollLabel']),
      amountPesewas: amount,
      applicationMode: _optionalText(json['applicationMode']),
    );
  }

  static RideToll? fromRideJson(Map<String, dynamic> json) {
    final nested = json['toll'];
    if (nested is Map) {
      final nestedMap = <String, dynamic>{
        for (final entry in nested.entries) entry.key.toString(): entry.value,
      };
      final amount = _positiveMoney(nestedMap['amountPesewas']);
      if (amount != null) {
        return RideToll(
          label: _displayLabel(nestedMap['label']),
          amountPesewas: amount,
          applicationMode: _optionalText(nestedMap['applicationMode']),
        );
      }
    }

    final flatAmount = _positiveMoney(json['tollFeePesewas']);
    if (flatAmount == null) return null;
    return RideToll(
      label: _displayLabel(json['tollLabel']),
      amountPesewas: flatAmount,
      applicationMode: _optionalText(json['tollApplicationMode']),
    );
  }

  final String label;
  final int amountPesewas;
  final String? applicationMode;

  String get amountDisplay => _formatGhs(amountPesewas);

  static int? _positiveMoney(Object? value) {
    final parsed = switch (value) {
      final num value => value,
      final String value => num.tryParse(value),
      _ => null,
    };
    if (parsed == null ||
        !parsed.isFinite ||
        parsed != parsed.truncateToDouble() ||
        parsed <= 0 ||
        parsed > 9007199254740991) {
      return null;
    }
    return parsed.toInt();
  }

  static String _displayLabel(Object? value) {
    final label = _optionalText(value);
    return label ?? 'Toll';
  }

  static String? _optionalText(Object? value) {
    if (value is! String) return null;
    final text = value.trim();
    return text.isEmpty ? null : text;
  }
}

/// Ride model representing a ride-hailing trip.
/// Money stored as int in pesewas (100 pesewas = GH₵1).
class Ride {
  const Ride({
    required this.id,
    required this.clientId,
    this.driverId,
    required this.status,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    required this.estimatedFarePesewas,
    this.hasEstimatedFareQuote = true,
    this.finalFarePesewas,
    this.totalPaidPesewas,
    this.prePromoFarePesewas,
    this.promoDiscountPesewas,
    this.loyaltyDiscountPesewas,
    this.platformDiscountPesewas,
    this.toll,
    this.promoApplied = false,
    this.clientPayableEstimatePesewas,
    this.estimatedProviderEarningsPesewas,
    this.collectFromClientPesewas,
    this.commissionPesewas,
    this.effectiveCommissionPesewas,
    this.providerSettlementBasisPesewas,
    this.commissionRatePercent,
    this.netPayoutPesewas,
    this.providerEarningsPesewas,
    this.financialsFinal,
    bool? hasFinancialsFinalContract,
    required this.estimatedDistanceKm,
    required this.estimatedDurationMins,
    this.actualDistanceKm,
    this.actualDurationMins,
    this.surgeMultiplier = 1.0,
    required this.paymentMethod,
    required this.createdAt,
    this.acceptedAt,
    this.arrivedAtPickupAt,
    this.pickedUpAt,
    this.completedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.clientName,
    this.clientPhone,
    this.clientPhotoUrl,
    this.clientRating,
    this.clientTripCount,
    this.driverName,
    this.driverPhone,
    this.stops = const [],
    this.routeRevision = 0,
  }) : hasFinancialsFinalContract =
            hasFinancialsFinalContract ?? financialsFinal != null;

  /// Parses a Ride from any of the three shapes the backend serves:
  ///   - the full persisted Ride (`GET /rides/:id`, status PATCH responses)
  ///   - the legacy slim `ride:request` socket broadcast (`{rideId, lat, lng, ...}`)
  ///   - the new `ride:new` socket broadcast (`{id, pickupLatitude, ...}`)
  ///
  /// The slim broadcasts intentionally omit fields the driver doesn't need
  /// to decide whether to accept (clientId, dropoff coords, paymentMethod,
  /// createdAt). Those become safe defaults here so the request modal can
  /// still render — full data arrives in the PATCH response after accept.
  factory Ride.fromJson(Map<String, dynamic> json) {
    double? _optionalNum(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return num.tryParse(v)?.toDouble();
      return null;
    }

    double _num(dynamic v, [double fallback = 0]) =>
        _optionalNum(v) ?? fallback;
    int _int(dynamic v, [int fallback = 0]) =>
        _optionalNum(v)?.toInt() ?? fallback;
    int? _optionalInt(dynamic v) => _optionalNum(v)?.toInt();
    int? _strictMoneyInt(dynamic v) =>
        v is int && v >= 0 && v <= 9007199254740991 ? v : null;
    DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v) : null;
    double _distanceKm() {
      final km = _optionalNum(
        json['estimatedDistanceKm'] ??
            json['distanceKm'] ??
            json['actualDistanceKm'],
      );
      if (km != null) return km;

      final meters = _optionalNum(
        json['estimatedDistanceMeters'] ??
            json['distanceMeters'] ??
            json['actualDistanceMeters'],
      );
      if (meters != null) return meters / 1000;

      return 0;
    }

    int _durationMins() {
      final minutes = _optionalNum(
        json['estimatedDurationMins'] ??
            json['durationMins'] ??
            json['actualDurationMins'],
      );
      if (minutes != null) return minutes.toInt();

      final seconds = _optionalNum(
        json['estimatedDurationSeconds'] ??
            json['durationSeconds'] ??
            json['actualDurationSeconds'],
      );
      if (seconds != null) return (seconds / 60).round();

      return 0;
    }

    // Backend serves the full ride entity with client info under a nested
    // `client` object (REST `GET /rides/:id`, `PATCH /rides/:id/status`),
    // while the slim `ride:new` socket broadcast inlines the same data at
    // top level. Read from whichever is populated so a single Ride model
    // works for both wire shapes.
    final clientObj = json['client'] is Map<String, dynamic>
        ? json['client'] as Map<String, dynamic>
        : const <String, dynamic>{};
    String? _clientStr(String topKey, [List<String> nestedKeys = const []]) {
      final top = json[topKey];
      if (top is String && top.isNotEmpty) return top;
      for (final k in nestedKeys) {
        final v = clientObj[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final clientFirstName = clientObj['firstName'] as String?;
    final clientLastName = clientObj['lastName'] as String?;
    final assembledName = (clientFirstName != null || clientLastName != null)
        ? [clientFirstName, clientLastName].whereType<String>().join(' ').trim()
        : null;

    // Driver identity may arrive nested under `driver: {...}` (full REST
    // snapshot) or flattened at the top level. Mirror the client-side
    // resolution so the rider-facing history can render the driver's real
    // name + number.
    final driverObj = json['driver'] is Map<String, dynamic>
        ? json['driver'] as Map<String, dynamic>
        : const <String, dynamic>{};
    String? _driverStr(String topKey, [List<String> nestedKeys = const []]) {
      final top = json[topKey];
      if (top is String && top.isNotEmpty) return top;
      for (final k in nestedKeys) {
        final v = driverObj[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final driverFirstName = driverObj['firstName'] as String?;
    final driverLastName = driverObj['lastName'] as String?;
    final assembledDriverName = (driverFirstName != null ||
            driverLastName != null)
        ? [driverFirstName, driverLastName].whereType<String>().join(' ').trim()
        : null;
    final status = RideStatus.fromString(
      json['status'] as String? ?? 'requested',
    );
    final actualDistanceMeters = _optionalNum(json['actualDistanceMeters']);
    final actualDurationSeconds = _optionalNum(json['actualDurationSeconds']);

    return Ride(
      id: (json['id'] ?? json['rideId']) as String,
      clientId: json['clientId'] as String? ?? clientObj['id'] as String? ?? '',
      driverId: json['driverId'] as String?,
      status: status,
      pickupAddress: json['pickupAddress'] as String? ?? '',
      dropoffAddress: json['dropoffAddress'] as String? ?? '',
      pickupLat: _num(
        json['pickupLat'] ?? json['pickupLatitude'] ?? json['lat'],
      ),
      pickupLng: _num(
        json['pickupLng'] ?? json['pickupLongitude'] ?? json['lng'],
      ),
      dropoffLat: _num(json['dropoffLat'] ?? json['dropoffLatitude']),
      dropoffLng: _num(json['dropoffLng'] ?? json['dropoffLongitude']),
      estimatedFarePesewas: _int(
        json['estimatedFarePesewas'] ?? json['totalFare'],
      ),
      hasEstimatedFareQuote: json.containsKey('estimatedFarePesewas') ||
          json.containsKey('totalFare'),
      finalFarePesewas: _optionalInt(
        json['finalFarePesewas'] ??
            (status == RideStatus.completed ? json['totalFare'] : null),
      ),
      totalPaidPesewas: _optionalInt(
        json['totalPaidPesewas'] ?? json['amountPaidPesewas'],
      ),
      prePromoFarePesewas: _optionalInt(json['prePromoFarePesewas']),
      promoDiscountPesewas: _optionalInt(json['promoDiscountPesewas']),
      loyaltyDiscountPesewas: _optionalInt(json['loyaltyDiscountPesewas']),
      platformDiscountPesewas: _optionalInt(json['platformDiscountPesewas']),
      toll: RideToll.fromRideJson(json),
      // Older payloads lack the explicit flag — infer from a non-zero discount.
      promoApplied: json['promoApplied'] == true ||
          (_optionalInt(json['promoDiscountPesewas']) ?? 0) > 0,
      clientPayableEstimatePesewas: _optionalInt(
        json['clientPayableEstimatePesewas'],
      ),
      estimatedProviderEarningsPesewas: _optionalInt(
        json['estimatedProviderEarningsPesewas'],
      ),
      collectFromClientPesewas: _optionalInt(
        json['collectFromClientPesewas'] ?? json['totalPaidPesewas'],
      ),
      commissionPesewas: _optionalInt(json['commissionPesewas']),
      effectiveCommissionPesewas: json['financialsFinal'] == true
          ? _strictMoneyInt(json['effectiveCommissionPesewas'])
          : _optionalInt(json['effectiveCommissionPesewas']),
      providerSettlementBasisPesewas: json['financialsFinal'] == true
          ? _strictMoneyInt(json['providerSettlementBasisPesewas'])
          : _optionalInt(json['providerSettlementBasisPesewas']),
      commissionRatePercent: _optionalNum(json['commissionRatePercent']),
      netPayoutPesewas: _optionalInt(json['netPayoutPesewas']),
      providerEarningsPesewas: json['financialsFinal'] == true
          ? _strictMoneyInt(json['providerEarningsPesewas'])
          : _optionalInt(json['providerEarningsPesewas']),
      financialsFinal: json['financialsFinal'] is bool
          ? json['financialsFinal'] as bool
          : null,
      hasFinancialsFinalContract: json.containsKey('financialsFinal'),
      estimatedDistanceKm: _distanceKm(),
      estimatedDurationMins: _durationMins(),
      actualDistanceKm: _optionalNum(json['actualDistanceKm']) ??
          (actualDistanceMeters != null ? actualDistanceMeters / 1000 : null),
      actualDurationMins: _optionalInt(json['actualDurationMins']) ??
          (actualDurationSeconds != null
              ? (actualDurationSeconds / 60).round()
              : null),
      surgeMultiplier: _num(json['surgeMultiplier'], 1.0),
      paymentMethod: json['paymentMethod'] as String? ?? 'cash',
      createdAt: _date(json['createdAt']) ?? DateTime.now(),
      acceptedAt: _date(json['acceptedAt']),
      arrivedAtPickupAt: _date(json['arrivedAtPickupAt']),
      pickedUpAt: _date(json['pickedUpAt']),
      completedAt: _date(json['completedAt']),
      cancelledAt: _date(json['cancelledAt']),
      cancellationReason: json['cancellationReason'] as String?,
      clientName:
          _clientStr('clientName', ['name', 'fullName']) ?? assembledName,
      clientPhone: _clientStr('clientPhone', ['phone', 'maskedPhone']),
      clientPhotoUrl: _clientStr('clientPhotoUrl', [
        'photoUrl',
        'profilePhotoUrl',
        'avatarUrl',
      ]),
      clientRating: (json['clientRating'] as num?)?.toDouble() ??
          (clientObj['rating'] as num?)?.toDouble(),
      clientTripCount: json['clientTripCount'] as int? ??
          (clientObj['tripCount'] as num?)?.toInt() ??
          (clientObj['totalRides'] as num?)?.toInt(),
      driverName:
          _driverStr('driverName', ['name', 'fullName']) ?? assembledDriverName,
      driverPhone: _driverStr('driverPhone', ['phone', 'maskedPhone']),
      stops: (json['stops'] as List<dynamic>?)
              ?.map((s) => RideStop.fromJson(s as Map<String, dynamic>))
              .toList() ??
          const [],
      routeRevision: _int(
        json['routeRevision'] ?? json['route_revision'] ?? json['revision'],
      ),
    );
  }

  final String id;
  final String clientId;
  final String? driverId;
  final RideStatus status;
  final String pickupAddress;
  final String dropoffAddress;
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final int estimatedFarePesewas;

  /// Distinguishes a legitimate zero quote from a slim legacy payload that
  /// omitted the quote and was parsed with the model's numeric zero default.
  final bool hasEstimatedFareQuote;
  final int? finalFarePesewas;
  final int? totalPaidPesewas;

  /// Metered fare before any promo/loyalty discount. Provider payouts and
  /// commission always derive from this figure (BR-49) — a promo never
  /// reduces what the provider earns.
  final int? prePromoFarePesewas;

  /// Platform-funded promo discount applied to what the client pays.
  final int? promoDiscountPesewas;

  /// Loyalty value funded by MyShop for this quote. This is separate from a
  /// promo campaign so provider-facing copy must describe the combined value
  /// as "MyShop covers", not strictly as a promo discount.
  final int? loyaltyDiscountPesewas;

  /// Authoritative combined platform-funded discount for the current quote.
  final int? platformDiscountPesewas;

  /// Optional server-authored access charge included in every quoted/final
  /// total. A missing, malformed, or non-positive charge is represented as
  /// null so UI surfaces can omit the row entirely for legacy/no-charge rides.
  final RideToll? toll;

  int get tollFeePesewas => toll?.amountPesewas ?? 0;
  bool get hasToll => tollFeePesewas > 0;

  /// True when a promo code/campaign discounted this ride.
  final bool promoApplied;

  /// Current amount quoted to the rider after promo and loyalty discounts.
  /// Unlike [estimatedFarePesewas], this additive field is unambiguous on the
  /// incoming-offer wire contract and may legitimately be zero.
  final int? clientPayableEstimatePesewas;

  /// Booking-time estimate of what the provider earns after commission.
  /// Do not substitute [providerEarningsPesewas], which is a settlement-time
  /// value and can change after the ride is completed.
  final int? estimatedProviderEarningsPesewas;

  /// What the client actually pays after discounts — for cash rides, the
  /// amount the driver should collect at drop-off.
  final int? collectFromClientPesewas;

  /// Historical policy commission before provider-specific relief. Older
  /// backends expose only this field, so provider surfaces may use it as a
  /// legacy fallback only when the additive settlement contract is absent.
  final int? commissionPesewas;

  /// Authoritative commission after provider relief/clawback rules. This is
  /// the amount that reconciles with [providerEarningsPesewas].
  final int? effectiveCommissionPesewas;

  /// Retained provider settlement basis after any refund adjustment. On an
  /// ordinary ride this equals [prePromoFarePesewas]; a partial/full refund may
  /// legitimately reduce it without rewriting the original trip fare.
  final int? providerSettlementBasisPesewas;
  final double? commissionRatePercent;

  /// Platform rail payout for the linked payment. For cash rides this is NOT
  /// the driver's earnings (it's the subsidy net of commission) — display
  /// earnings from [providerEarningsPesewas].
  final int? netPayoutPesewas;

  /// Server-authored provider earnings against the applicable settlement
  /// basis. The basis is normally the full pre-promo fare, but can be lower
  /// after a refund.
  final int? providerEarningsPesewas;

  /// Whether the backend has finished creating the immutable payment ledger
  /// snapshot. Consult [hasFinancialsFinalContract] to distinguish an absent
  /// legacy key from an explicitly malformed value.
  final bool? financialsFinal;

  /// True when the wire payload explicitly included `financialsFinal`, even
  /// if its value was malformed. Only key absence may use legacy financial
  /// conservation rules.
  final bool hasFinancialsFinalContract;
  final double estimatedDistanceKm;
  final int estimatedDurationMins;
  final double? actualDistanceKm;
  final int? actualDurationMins;
  final double surgeMultiplier;
  final String paymentMethod;
  final DateTime createdAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAtPickupAt;
  final DateTime? pickedUpAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? clientName;

  /// Counterparty's real, dialable phone number. During the pilot the platform
  /// no longer masks these — the backend serves the live number on active
  /// rides and (for a limited window) on completed-ride snapshots so the two
  /// sides can reconnect. Null when the backend omits it / the window closed.
  final String? clientPhone;
  final String? clientPhotoUrl;
  final double? clientRating;
  final int? clientTripCount;
  final String? driverName;

  /// Driver's real, dialable phone number (see [clientPhone]).
  final String? driverPhone;
  final List<RideStop> stops;

  /// Monotonic server-authored route version. Legacy payloads omit it and
  /// therefore remain revision zero. Route-change consumers must never apply
  /// a snapshot whose revision is lower than the revision already displayed.
  final int routeRevision;

  /// Display fare in GHS format
  String get estimatedFareDisplay => _formatGhs(estimatedFarePesewas);
  String get finalFareDisplay => finalFarePesewas != null
      ? _formatGhs(finalFarePesewas!)
      : estimatedFareDisplay;
  String get paidFareDisplay => totalPaidPesewas != null
      ? _formatGhs(totalPaidPesewas!)
      : finalFareDisplay;

  /// The full trip fare, inclusive of any positive access charge. A completed
  /// legacy payload may expose both a full `finalFarePesewas` and a discounted
  /// `totalPaidPesewas`; the full fare must win. Provider commission and
  /// earnings remain server-authored because the access charge is excluded
  /// from commission but passed through fully to the provider.
  int get tripFarePesewas =>
      prePromoFarePesewas ??
      finalFarePesewas ??
      totalPaidPesewas ??
      estimatedFarePesewas;
  String get tripFareDisplay => _formatGhs(tripFarePesewas);

  int? get _candidateProviderCommissionPesewas {
    if (hasFinancialsFinalContract) {
      if (financialsFinal != true) return null;
      return effectiveCommissionPesewas;
    }
    return effectiveCommissionPesewas ?? commissionPesewas;
  }

  /// True only when commission and earnings form one non-negative,
  /// server-authored pair that conserves the applicable settlement basis.
  /// New final snapshots must publish that basis explicitly so legitimate
  /// refund adjustments do not look malformed. Legacy snapshots still
  /// conserve against the original full trip fare.
  bool get hasConservedProviderFinancials {
    final commission = _candidateProviderCommissionPesewas;
    final earnings = providerEarningsPesewas;
    final fare = tripFarePesewas;
    final basis = hasFinancialsFinalContract
        ? financialsFinal == true
            ? providerSettlementBasisPesewas
            : null
        : fare;
    return commission != null &&
        earnings != null &&
        basis != null &&
        commission >= 0 &&
        earnings >= 0 &&
        fare >= 0 &&
        basis >= 0 &&
        basis <= fare &&
        commission <= basis &&
        earnings == basis - commission;
  }

  /// Provider-facing commission with additive-contract fail-closed behavior.
  /// Commission and earnings are deliberately exposed together or not at all.
  int? get providerCommissionPesewas => hasConservedProviderFinancials
      ? _candidateProviderCommissionPesewas
      : null;

  /// Provider earnings are server authority and must never be recomputed from
  /// fare and commission in the app. See [hasConservedProviderFinancials].
  int? get settledProviderEarningsPesewas =>
      hasConservedProviderFinancials ? providerEarningsPesewas : null;

  /// Conserved provider basis paired with commission and earnings. Null when
  /// the financial pair is pending or malformed.
  int? get settledProviderSettlementBasisPesewas =>
      hasConservedProviderFinancials
          ? (hasFinancialsFinalContract
              ? providerSettlementBasisPesewas
              : tripFarePesewas)
          : null;

  String get distanceDisplay => '${estimatedDistanceKm.toStringAsFixed(1)} km';
  String get durationDisplay => '$estimatedDurationMins mins';

  bool get hasSurge => surgeMultiplier > 1.0;
  String get surgeDisplay => '${surgeMultiplier.toStringAsFixed(1)}x';

  Ride copyWith({
    RideStatus? status,
    List<RideStop>? stops,
    String? dropoffAddress,
    double? dropoffLat,
    double? dropoffLng,
    int? estimatedFarePesewas,
    int? clientPayableEstimatePesewas,
    int? promoDiscountPesewas,
    bool? promoApplied,
    RideToll? toll,
    bool replaceRouteAdjustments = false,
    double? estimatedDistanceKm,
    int? estimatedDurationMins,
    int? routeRevision,
  }) {
    return Ride(
      id: id,
      clientId: clientId,
      driverId: driverId,
      status: status ?? this.status,
      pickupAddress: pickupAddress,
      dropoffAddress: dropoffAddress ?? this.dropoffAddress,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropoffLat: dropoffLat ?? this.dropoffLat,
      dropoffLng: dropoffLng ?? this.dropoffLng,
      estimatedFarePesewas: estimatedFarePesewas ?? this.estimatedFarePesewas,
      hasEstimatedFareQuote: hasEstimatedFareQuote,
      finalFarePesewas: finalFarePesewas,
      totalPaidPesewas: totalPaidPesewas,
      prePromoFarePesewas: prePromoFarePesewas,
      promoDiscountPesewas: replaceRouteAdjustments
          ? promoDiscountPesewas
          : this.promoDiscountPesewas,
      loyaltyDiscountPesewas: loyaltyDiscountPesewas,
      platformDiscountPesewas: platformDiscountPesewas,
      toll: replaceRouteAdjustments ? toll : this.toll,
      promoApplied:
          replaceRouteAdjustments ? (promoApplied ?? false) : this.promoApplied,
      clientPayableEstimatePesewas:
          clientPayableEstimatePesewas ?? this.clientPayableEstimatePesewas,
      estimatedProviderEarningsPesewas: estimatedProviderEarningsPesewas,
      collectFromClientPesewas: collectFromClientPesewas,
      commissionPesewas: commissionPesewas,
      effectiveCommissionPesewas: effectiveCommissionPesewas,
      providerSettlementBasisPesewas: providerSettlementBasisPesewas,
      commissionRatePercent: commissionRatePercent,
      netPayoutPesewas: netPayoutPesewas,
      providerEarningsPesewas: providerEarningsPesewas,
      financialsFinal: financialsFinal,
      hasFinancialsFinalContract: hasFinancialsFinalContract,
      estimatedDistanceKm: estimatedDistanceKm ?? this.estimatedDistanceKm,
      estimatedDurationMins:
          estimatedDurationMins ?? this.estimatedDurationMins,
      actualDistanceKm: actualDistanceKm,
      actualDurationMins: actualDurationMins,
      surgeMultiplier: surgeMultiplier,
      paymentMethod: paymentMethod,
      createdAt: createdAt,
      acceptedAt: acceptedAt,
      arrivedAtPickupAt: arrivedAtPickupAt,
      pickedUpAt: pickedUpAt,
      completedAt: completedAt,
      cancelledAt: cancelledAt,
      cancellationReason: cancellationReason,
      clientName: clientName,
      clientPhone: clientPhone,
      clientPhotoUrl: clientPhotoUrl,
      clientRating: clientRating,
      clientTripCount: clientTripCount,
      driverName: driverName,
      driverPhone: driverPhone,
      stops: stops ?? this.stops,
      routeRevision: routeRevision ?? this.routeRevision,
    );
  }
}

/// A stop on a multi-stop ride.
class RideStop {
  const RideStop({
    required this.address,
    required this.lat,
    required this.lng,
    this.arrivedAt,
  });

  factory RideStop.fromJson(Map<String, dynamic> json) {
    return RideStop(
      address: json['address'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      arrivedAt: json['arrivedAt'] != null
          ? DateTime.parse(json['arrivedAt'] as String)
          : null,
    );
  }

  final String address;
  final double lat;
  final double lng;
  final DateTime? arrivedAt;
}

/// Ride lifecycle status
enum RideStatus {
  requested,
  accepted,
  driverEnRoute,
  arrived,
  inProgress,
  completed,
  cancelled;

  bool get isActive =>
      this == accepted ||
      this == driverEnRoute ||
      this == arrived ||
      this == inProgress;

  /// Parse a snake_case status string from the backend.
  /// `arrived` is accepted as an alias for `arrived_at_pickup` in case
  /// older payloads or other clients emit the short form.
  static RideStatus fromString(String value) {
    switch (value) {
      case 'requested':
        return RideStatus.requested;
      case 'accepted':
        return RideStatus.accepted;
      case 'driver_en_route':
        return RideStatus.driverEnRoute;
      case 'arrived_at_pickup':
      case 'arrived':
        return RideStatus.arrived;
      case 'in_progress':
        return RideStatus.inProgress;
      case 'completed':
        return RideStatus.completed;
      case 'cancelled':
        return RideStatus.cancelled;
      default:
        return RideStatus.requested;
    }
  }

  /// Convert to the snake_case string the backend expects on
  /// `PATCH /rides/:id/status`. Backend's `UpdatableRideStatus` enum is
  /// `driver_en_route | arrived_at_pickup | in_progress | completed`.
  String toJson() {
    switch (this) {
      case RideStatus.driverEnRoute:
        return 'driver_en_route';
      case RideStatus.arrived:
        return 'arrived_at_pickup';
      case RideStatus.inProgress:
        return 'in_progress';
      default:
        return name;
    }
  }
}

/// Trip summary with fare breakdown (displayed after ride completion).
class TripSummary {
  const TripSummary({
    required this.rideId,
    required this.clientName,
    this.clientPhotoUrl,
    required this.clientRating,
    required this.paymentMethod,
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.distanceKm,
    required this.durationMins,
    required this.baseFarePesewas,
    required this.distanceFarePesewas,
    required this.timeFarePesewas,
    this.surgeFarePesewas = 0,
    this.taxesPesewas = 0,
    this.promoPesewas = 0,
    this.loyaltyPesewas = 0,
    this.toll,
    this.promoApplied = false,
    required this.totalFarePesewas,
    this.collectFromClientPesewas,
    this.commissionPesewas,
    this.commissionRatePercent,
    this.commissionIsEffective = false,
    this.providerSettlementBasisPesewas,
    this.netEarningsPesewas,
    required this.payoutMethod,
    required this.payoutStatus,
  });

  final String rideId;
  final String clientName;
  final String? clientPhotoUrl;
  final double clientRating;
  final String paymentMethod;
  final String pickupAddress;
  final String dropoffAddress;
  final double distanceKm;
  final int durationMins;
  final int baseFarePesewas;
  final int distanceFarePesewas;
  final int timeFarePesewas;
  final int surgeFarePesewas;
  final int taxesPesewas;
  final int promoPesewas;
  final int loyaltyPesewas;

  /// Full pass-through reimbursement included in [totalFarePesewas].
  /// Commission/earnings remain backend-authored and are never recalculated
  /// from this value on-device.
  final RideToll? toll;

  /// True when a platform promo discounted what the client pays. The provider
  /// is still paid on the full [totalFarePesewas] (BR-49).
  final bool promoApplied;

  /// The full pre-promo trip fare, inclusive of any positive access charge.
  /// Server-authored commission and earnings apply the pass-through rules.
  final int totalFarePesewas;

  /// What the client hands over after the promo — for cash trips, the amount
  /// to collect at drop-off. Null when unknown (legacy payloads).
  final int? collectFromClientPesewas;
  final int? commissionPesewas;
  final double? commissionRatePercent;
  final bool commissionIsEffective;
  final int? providerSettlementBasisPesewas;
  final int? netEarningsPesewas;
  final String payoutMethod;
  final String payoutStatus;

  String get totalFareDisplay => _formatGhs(totalFarePesewas);
  String get collectFromClientDisplay => collectFromClientPesewas == null
      ? 'Pending'
      : _formatGhs(collectFromClientPesewas!);
  String get commissionDisplay =>
      commissionPesewas == null ? 'Pending' : _formatGhs(commissionPesewas!);
  String get netEarningsDisplay =>
      netEarningsPesewas == null ? 'Pending' : _formatGhs(netEarningsPesewas!);
  String get providerSettlementBasisDisplay =>
      providerSettlementBasisPesewas == null
          ? 'Pending'
          : _formatGhs(providerSettlementBasisPesewas!);
  bool get hasRefundAdjustedSettlement =>
      providerSettlementBasisPesewas != null &&
      providerSettlementBasisPesewas != totalFarePesewas;

  String get commissionLabel {
    if (commissionIsEffective) return 'Effective Platform Commission';
    final rate = commissionRatePercent;
    if (rate == null) return 'Platform Commission';
    final formatted = rate == rate.roundToDouble()
        ? rate.toInt().toString()
        : rate
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
    return 'Platform Commission ($formatted%)';
  }
}

/// Payout record for the earnings dashboard.
class PayoutRecord {
  const PayoutRecord({
    required this.id,
    required this.method,
    required this.amountPesewas,
    required this.status,
    required this.createdAt,
    this.reference,
  });

  final String id;
  final String method;
  final int amountPesewas;
  final String status;
  final DateTime createdAt;
  final String? reference;

  String get amountDisplay => _formatGhs(amountPesewas);
}

String _formatGhs(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble() && ghs >= 1) {
    return 'GHS ${ghs.toStringAsFixed(0)}';
  }
  return 'GHS ${ghs.toStringAsFixed(2)}';
}
