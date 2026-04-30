/// Earnings models matching the new backend split:
///   - GET /v1/payments/earnings/today-card  → [EarningsTodayCard]
///   - GET /v1/payments/earnings/summary     → [EarningsSummary]
///   - GET /v1/payments/earnings/report      → [EarningsReport]
///
/// All money values are int pesewas (100 pesewas = ₵1). All ISO timestamps
/// are UTC.

/// Selected period for the summary + preset-mode report endpoints.
enum EarningsPeriod {
  today,
  week,
  month;

  String get wire => name; // 'today' | 'week' | 'month'

  static EarningsPeriod parse(String? raw) {
    switch (raw) {
      case 'today':
        return EarningsPeriod.today;
      case 'week':
        return EarningsPeriod.week;
      case 'month':
        return EarningsPeriod.month;
    }
    return EarningsPeriod.week;
  }
}

/// Time-bucket size for the report's `series[]`.
enum EarningsGranularity {
  day,
  week,
  month;

  String get wire => name;

  static EarningsGranularity parse(String? raw) {
    switch (raw) {
      case 'day':
        return EarningsGranularity.day;
      case 'week':
        return EarningsGranularity.week;
      case 'month':
        return EarningsGranularity.month;
    }
    return EarningsGranularity.day;
  }
}

/// Active role passed via `?role=…`. The mobile should always pass this
/// explicitly so a future second profile doesn't leak earnings across roles.
enum EarningsRole {
  driver,
  artisan;

  String get wire => name;

  static EarningsRole parse(String? raw) =>
      raw == 'artisan' ? EarningsRole.artisan : EarningsRole.driver;
}

/// Backend error codes the earnings endpoints can return.
class EarningsErrorCodes {
  EarningsErrorCodes._();

  static const roleNotResolved = 'ROLE_NOT_RESOLVED';
  static const providerNotFound = 'PROVIDER_NOT_FOUND';
  static const rangeAmbiguous = 'EARNINGS_RANGE_AMBIGUOUS';
  static const rangeInvalid = 'EARNINGS_RANGE_INVALID';
  static const rangeTooLarge = 'EARNINGS_RANGE_TOO_LARGE';
}

// ────────────────────────────────────────────────────────────────────────────
// Today-card — homepage "Today's earnings"
// ────────────────────────────────────────────────────────────────────────────

/// Driver/artisan homepage card. Mirrors `GET /v1/payments/earnings/today-card`.
///
/// `bookingsCount` is the role-agnostic name for what the backend returns as
/// either `tripsCount` (driver) or `jobsCount` (artisan).
class EarningsTodayCard {
  const EarningsTodayCard({
    required this.role,
    required this.date,
    required this.bookingsCount,
    required this.hoursWorkedMinutes,
    required this.tipsEarnedPesewas,
    required this.netEarningsPesewas,
  });

  factory EarningsTodayCard.fromJson(Map<String, dynamic> json) {
    final role = EarningsRole.parse(json['role'] as String?);
    final count = (json['tripsCount'] ?? json['jobsCount'] ?? 0) as num;
    return EarningsTodayCard(
      role: role,
      date: (json['date'] as String?) ?? '',
      bookingsCount: count.toInt(),
      hoursWorkedMinutes: (json['hoursWorkedMinutes'] as num?)?.toInt() ?? 0,
      tipsEarnedPesewas: (json['tipsEarnedPesewas'] as num?)?.toInt() ?? 0,
      netEarningsPesewas: (json['netEarningsPesewas'] as num?)?.toInt() ?? 0,
    );
  }

  static EarningsTodayCard empty(EarningsRole role) => EarningsTodayCard(
        role: role,
        date: '',
        bookingsCount: 0,
        hoursWorkedMinutes: 0,
        tipsEarnedPesewas: 0,
        netEarningsPesewas: 0,
      );

  final EarningsRole role;

  /// `YYYY-MM-DD` in UTC (Ghana = UTC+0).
  final String date;

  /// `tripsCount` for drivers, `jobsCount` for artisans.
  final int bookingsCount;

  /// Active trip/job time only — does NOT include online idle time.
  final int hoursWorkedMinutes;

  final int tipsEarnedPesewas;

  /// Net of commission. Drives the homepage headline number.
  final int netEarningsPesewas;
}

// ────────────────────────────────────────────────────────────────────────────
// Summary — earnings tab top card
// ────────────────────────────────────────────────────────────────────────────

/// One bucket of the summary's gap-filled series. Each entry is a single day
/// when `granularity = day` (the only value backend returns for presets).
class EarningsSummaryPoint {
  const EarningsSummaryPoint({
    required this.bucketStart,
    required this.netPesewas,
  });

  factory EarningsSummaryPoint.fromJson(Map<String, dynamic> json) {
    return EarningsSummaryPoint(
      bucketStart:
          DateTime.tryParse(json['bucketStart'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      netPesewas: (json['netPesewas'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime bucketStart;
  final int netPesewas;
}

/// Mirrors `GET /v1/payments/earnings/summary`.
class EarningsSummary {
  const EarningsSummary({
    required this.role,
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.availableBalancePesewas,
    required this.todayAvailableBalancePesewas,
    required this.weeklyAvailableBalancePesewas,
    required this.netEarningsPesewas,
    required this.paidOutPesewas,
    required this.series,
    required this.granularity,
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    return EarningsSummary(
      role: EarningsRole.parse(json['role'] as String?),
      period: EarningsPeriod.parse(json['period'] as String?),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '')?.toUtc(),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? '')?.toUtc(),
      availableBalancePesewas:
          (json['availableBalancePesewas'] as num?)?.toInt() ?? 0,
      todayAvailableBalancePesewas:
          (json['todayAvailableBalancePesewas'] as num?)?.toInt() ?? 0,
      weeklyAvailableBalancePesewas:
          (json['weeklyAvailableBalancePesewas'] as num?)?.toInt() ?? 0,
      netEarningsPesewas: (json['netEarningsPesewas'] as num?)?.toInt() ?? 0,
      paidOutPesewas: (json['paidOutPesewas'] as num?)?.toInt() ?? 0,
      series: (json['series'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(EarningsSummaryPoint.fromJson)
              .toList(growable: false) ??
          const <EarningsSummaryPoint>[],
      granularity: EarningsGranularity.parse(json['granularity'] as String?),
    );
  }

  static EarningsSummary empty(EarningsRole role, EarningsPeriod period) =>
      EarningsSummary(
        role: role,
        period: period,
        startDate: null,
        endDate: null,
        availableBalancePesewas: 0,
        todayAvailableBalancePesewas: 0,
        weeklyAvailableBalancePesewas: 0,
        netEarningsPesewas: 0,
        paidOutPesewas: 0,
        series: const [],
        granularity: EarningsGranularity.day,
      );

  final EarningsRole role;
  final EarningsPeriod period;
  final DateTime? startDate;
  final DateTime? endDate;

  /// Period-agnostic withdrawable balance. Drives the payout-button gate.
  final int availableBalancePesewas;

  /// Net earnings from today only — always shown alongside the period.
  final int todayAvailableBalancePesewas;

  /// Net earnings over the last 7 days.
  final int weeklyAvailableBalancePesewas;

  /// Net earnings over the **selected period**.
  final int netEarningsPesewas;

  /// Money already disbursed in the selected period. Excludes cash trips.
  final int paidOutPesewas;

  /// Gap-filled time series — every bucket present even with `netPesewas: 0`.
  final List<EarningsSummaryPoint> series;

  final EarningsGranularity granularity;
}

// ────────────────────────────────────────────────────────────────────────────
// Report — detailed report view
// ────────────────────────────────────────────────────────────────────────────

/// One bucket of the report's gap-filled series. Carries every metric so the
/// same data can drive multiple chart layers (gross + tips, net stack, etc.).
class EarningsReportPoint {
  const EarningsReportPoint({
    required this.bucketStart,
    required this.grossPesewas,
    required this.netPesewas,
    required this.commissionPesewas,
    required this.tipsPesewas,
    required this.count,
  });

  factory EarningsReportPoint.fromJson(Map<String, dynamic> json) {
    return EarningsReportPoint(
      bucketStart:
          DateTime.tryParse(json['bucketStart'] as String? ?? '')?.toUtc() ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      grossPesewas: (json['grossPesewas'] as num?)?.toInt() ?? 0,
      netPesewas: (json['netPesewas'] as num?)?.toInt() ?? 0,
      commissionPesewas: (json['commissionPesewas'] as num?)?.toInt() ?? 0,
      tipsPesewas: (json['tipsPesewas'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  final DateTime bucketStart;
  final int grossPesewas;
  final int netPesewas;
  final int commissionPesewas;
  final int tipsPesewas;
  final int count;
}

/// Mirrors `GET /v1/payments/earnings/report`.
class EarningsReport {
  const EarningsReport({
    required this.role,
    required this.startDate,
    required this.endDate,
    required this.granularity,
    required this.grossEarningsPesewas,
    required this.netEarningsPesewas,
    required this.commissionChargedPesewas,
    required this.tipsEarnedPesewas,
    required this.bookingsCompleted,
    required this.averageFarePesewas,
    required this.hoursWorkedMinutes,
    required this.trendPct,
    required this.series,
  });

  factory EarningsReport.fromJson(Map<String, dynamic> json) {
    final completed =
        (json['tripsCompleted'] ?? json['jobsCompleted'] ?? 0) as num;
    return EarningsReport(
      role: EarningsRole.parse(json['role'] as String?),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? '')?.toUtc(),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? '')?.toUtc(),
      granularity: EarningsGranularity.parse(json['granularity'] as String?),
      grossEarningsPesewas:
          (json['grossEarningsPesewas'] as num?)?.toInt() ?? 0,
      netEarningsPesewas: (json['netEarningsPesewas'] as num?)?.toInt() ?? 0,
      commissionChargedPesewas:
          (json['commissionChargedPesewas'] as num?)?.toInt() ?? 0,
      tipsEarnedPesewas: (json['tipsEarnedPesewas'] as num?)?.toInt() ?? 0,
      bookingsCompleted: completed.toInt(),
      averageFarePesewas: (json['averageFarePesewas'] as num?)?.toInt() ?? 0,
      hoursWorkedMinutes: (json['hoursWorkedMinutes'] as num?)?.toInt() ?? 0,
      trendPct: (json['trendPct'] as num?)?.toDouble(),
      series: (json['series'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(EarningsReportPoint.fromJson)
              .toList(growable: false) ??
          const <EarningsReportPoint>[],
    );
  }

  static EarningsReport empty(EarningsRole role) => EarningsReport(
        role: role,
        startDate: null,
        endDate: null,
        granularity: EarningsGranularity.day,
        grossEarningsPesewas: 0,
        netEarningsPesewas: 0,
        commissionChargedPesewas: 0,
        tipsEarnedPesewas: 0,
        bookingsCompleted: 0,
        averageFarePesewas: 0,
        hoursWorkedMinutes: 0,
        trendPct: null,
        series: const [],
      );

  final EarningsRole role;
  final DateTime? startDate;
  final DateTime? endDate;
  final EarningsGranularity granularity;

  /// Gross — includes cash AND in-app trips.
  final int grossEarningsPesewas;
  final int netEarningsPesewas;
  final int commissionChargedPesewas;
  final int tipsEarnedPesewas;

  /// `tripsCompleted` for drivers, `jobsCompleted` for artisans.
  final int bookingsCompleted;

  /// Integer-rounded `gross / count`. Backend returns 0 when `count == 0`.
  final int averageFarePesewas;

  /// Active trip/job time only.
  final int hoursWorkedMinutes;

  /// Null when the previous equal-length window had zero earnings — render
  /// as `—` or hide the badge.
  final double? trendPct;

  final List<EarningsReportPoint> series;
}

// ────────────────────────────────────────────────────────────────────────────
// Report request shape
// ────────────────────────────────────────────────────────────────────────────

/// Identifies a report query — either a preset period OR a custom date range.
/// Used as the family key for the report provider so different queries cache
/// independently.
class EarningsReportQuery {
  const EarningsReportQuery.preset({
    required this.role,
    required EarningsPeriod period,
  })  : period = period,
        from = null,
        to = null,
        granularity = null;

  const EarningsReportQuery.range({
    required this.role,
    required DateTime this.from,
    required DateTime this.to,
    this.granularity,
  }) : period = null;

  final EarningsRole role;
  final EarningsPeriod? period;
  final DateTime? from;
  final DateTime? to;
  final EarningsGranularity? granularity;

  bool get isPreset => period != null;

  @override
  bool operator ==(Object other) =>
      other is EarningsReportQuery &&
      other.role == role &&
      other.period == period &&
      other.from == from &&
      other.to == to &&
      other.granularity == granularity;

  @override
  int get hashCode => Object.hash(role, period, from, to, granularity);
}

// ────────────────────────────────────────────────────────────────────────────
// Errors
// ────────────────────────────────────────────────────────────────────────────

/// Thrown by the earnings service so callers can pattern-match on the
/// backend's machine-readable error code.
class EarningsApiException implements Exception {
  const EarningsApiException({required this.code, this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'EarningsApiException($code): ${message ?? ''}';
}
