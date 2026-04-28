/// Earnings summary displayed on the driver home and earnings dashboard.
/// Combines two `GET /payments/earnings?period=…` responses (today + week)
/// because the backend returns one period per call.
///
/// Money values are int pesewas (100 pesewas = ₵1).
class DriverEarnings {
  const DriverEarnings({
    required this.todayAmountPesewas,
    required this.todayTrips,
    required this.weekAmountPesewas,
    required this.weekTrips,
    required this.todayCommissionPesewas,
    required this.weekCommissionPesewas,
    required this.todayTipsPesewas,
    required this.weekTipsPesewas,
    required this.weekTrendPct,
    this.availableBalancePesewas = 0,
    this.todayPaidOutPesewas = 0,
    this.weekPaidOutPesewas = 0,
    this.peakHours = const [],
    this.hoursOnline = 0,
    this.acceptanceRate = 0,
  });

  /// Builds a [DriverEarnings] by merging two backend payloads — one for
  /// `today` and one for `week`. The backend's per-period response shape is:
  /// `{ totalEarningsPesewas, totalCommissionPesewas, totalTipsPesewas,
  ///    completedRides, trendPct, availableBalancePesewas, paidOutPesewas,
  ///    peakHours }`.
  /// (See `apps/api/src/modules/payment/payment.service.ts` `EarningsResponse`.)
  ///
  /// `availableBalancePesewas` is not period-bound — both payloads carry the
  /// same current value, so we prefer `today` and fall back to `week`.
  factory DriverEarnings.fromBackendPeriods({
    required Map<String, dynamic> today,
    required Map<String, dynamic> week,
  }) {
    int _int(Map<String, dynamic> j, String k) =>
        (j[k] as num?)?.toInt() ?? 0;
    double? _doubleOpt(Map<String, dynamic> j, String k) =>
        (j[k] as num?)?.toDouble();

    final available = _int(today, 'availableBalancePesewas') > 0
        ? _int(today, 'availableBalancePesewas')
        : _int(week, 'availableBalancePesewas');

    return DriverEarnings(
      todayAmountPesewas: _int(today, 'totalEarningsPesewas'),
      todayTrips: _int(today, 'completedRides'),
      weekAmountPesewas: _int(week, 'totalEarningsPesewas'),
      weekTrips: _int(week, 'completedRides'),
      todayCommissionPesewas: _int(today, 'totalCommissionPesewas'),
      weekCommissionPesewas: _int(week, 'totalCommissionPesewas'),
      todayTipsPesewas: _int(today, 'totalTipsPesewas'),
      weekTipsPesewas: _int(week, 'totalTipsPesewas'),
      weekTrendPct: _doubleOpt(week, 'trendPct'),
      availableBalancePesewas: available,
      todayPaidOutPesewas: _int(today, 'paidOutPesewas'),
      weekPaidOutPesewas: _int(week, 'paidOutPesewas'),
      peakHours: (week['peakHours'] as List<dynamic>?)
              ?.whereType<Map<String, dynamic>>()
              .map(EarningsPeakHour.fromJson)
              .toList() ??
          const [],
    );
  }

  /// Legacy single-period factory. Kept for screens that only need
  /// today's totals — fills weekly fields with the same numbers so the
  /// dashboard's "today" section renders even if the week call fails.
  factory DriverEarnings.fromJson(Map<String, dynamic> json) {
    return DriverEarnings.fromBackendPeriods(today: json, week: json);
  }

  static const empty = DriverEarnings(
    todayAmountPesewas: 0,
    todayTrips: 0,
    weekAmountPesewas: 0,
    weekTrips: 0,
    todayCommissionPesewas: 0,
    weekCommissionPesewas: 0,
    todayTipsPesewas: 0,
    weekTipsPesewas: 0,
    weekTrendPct: null,
  );

  final int todayAmountPesewas;
  final int todayTrips;
  final int weekAmountPesewas;
  final int weekTrips;
  final int todayCommissionPesewas;
  final int weekCommissionPesewas;
  final int todayTipsPesewas;
  final int weekTipsPesewas;

  /// Currently withdrawable balance (pesewas), authoritative source for
  /// the payout-button gate. Sum of escrow-released payments not yet
  /// disbursed. Not period-bound.
  final int availableBalancePesewas;

  /// Money disbursed to the provider today (pesewas).
  final int todayPaidOutPesewas;

  /// Money disbursed to the provider this week (pesewas).
  final int weekPaidOutPesewas;

  /// Percentage trend vs. the previous week (negative = down). Null when
  /// the backend doesn't have enough history to compute it.
  final double? weekTrendPct;

  /// Peak hour density returned by the week query — used to render the
  /// "best driving times" chart on the dashboard. Each entry is a single
  /// hour-of-week bucket; missing buckets imply zero rides in that hour.
  final List<EarningsPeakHour> peakHours;

  /// Hours-online and acceptance-rate are displayed elsewhere on the
  /// dashboard but not yet returned by `/payments/earnings`. Kept on the
  /// model so the surface compiles while the backend catches up.
  final double hoursOnline;
  final double acceptanceRate;

  /// Net of commission — what actually lands in the provider's wallet.
  ///
  /// Backend's `totalEarningsPesewas` is already `_sum(netPayoutPesewas)`
  /// — i.e. gross minus commission. These are pass-throughs so callers
  /// have a semantically named accessor without re-deducting commission.
  int get todayNetPesewas => todayAmountPesewas;

  int get weekNetPesewas => weekAmountPesewas;

  /// Gross revenue (pre-commission) — net plus the commission already
  /// deducted upstream. Useful for "you billed X, we took Y, you keep Z"
  /// breakdowns.
  int get todayGrossPesewas => todayAmountPesewas + todayCommissionPesewas;

  int get weekGrossPesewas => weekAmountPesewas + weekCommissionPesewas;

  /// Display today's earnings in GHS: ₵47, ₵1,250
  String get todayDisplay => _ghs(todayAmountPesewas);

  /// Display week's earnings in GHS
  String get weekDisplay => _ghs(weekAmountPesewas);

  String get todayCommissionDisplay => _ghs(todayCommissionPesewas);
  String get weekCommissionDisplay => _ghs(weekCommissionPesewas);
  String get todayTipsDisplay => _ghs(todayTipsPesewas);
  String get weekTipsDisplay => _ghs(weekTipsPesewas);
  String get todayNetDisplay => _ghs(todayNetPesewas);
  String get weekNetDisplay => _ghs(weekNetPesewas);

  String get hoursOnlineDisplay {
    final hours = hoursOnline.floor();
    final minutes = ((hoursOnline - hours) * 60).round();
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  String get acceptanceRateDisplay => '${(acceptanceRate * 100).round()}%';
}

/// One row of the backend's `peakHours` response.
class EarningsPeakHour {
  const EarningsPeakHour({
    required this.hour,
    required this.dayOfWeek,
    required this.count,
  });

  factory EarningsPeakHour.fromJson(Map<String, dynamic> json) =>
      EarningsPeakHour(
        hour: (json['hour'] as num?)?.toInt() ?? 0,
        dayOfWeek: (json['dayOfWeek'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  /// 0–23.
  final int hour;

  /// 0=Sunday … 6=Saturday (Postgres' `EXTRACT(DOW FROM …)` convention).
  final int dayOfWeek;

  final int count;
}

String _ghs(int pesewas) {
  final ghs = (pesewas / 100).ceil();
  if (ghs < 1000) return '₵$ghs';
  final str = ghs.toString();
  final buffer = StringBuffer('₵');
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return buffer.toString();
}
