/// Today's earnings summary displayed on the driver home screen.
/// Money is stored as int in pesewas (100 pesewas = ₵1).
class DriverEarnings {
  const DriverEarnings({
    required this.todayAmountPesewas,
    required this.todayTrips,
    required this.weekAmountPesewas,
    required this.hoursOnline,
    required this.acceptanceRate,
  });

  factory DriverEarnings.fromJson(Map<String, dynamic> json) {
    return DriverEarnings(
      todayAmountPesewas: json['todayAmountPesewas'] as int? ?? 0,
      todayTrips: json['todayTrips'] as int? ?? 0,
      weekAmountPesewas: json['weekAmountPesewas'] as int? ?? 0,
      hoursOnline: (json['hoursOnline'] as num?)?.toDouble() ?? 0,
      acceptanceRate: (json['acceptanceRate'] as num?)?.toDouble() ?? 0,
    );
  }

  static const empty = DriverEarnings(
    todayAmountPesewas: 0,
    todayTrips: 0,
    weekAmountPesewas: 0,
    hoursOnline: 0,
    acceptanceRate: 0,
  );

  final int todayAmountPesewas;
  final int todayTrips;
  final int weekAmountPesewas;
  final double hoursOnline;
  final double acceptanceRate;

  /// Display today's earnings in GHS: ₵47, ₵1,250
  String get todayDisplay {
    final ghs = (todayAmountPesewas / 100).ceil();
    return '₵${_formatNumber(ghs)}';
  }

  /// Display week's earnings in GHS
  String get weekDisplay {
    final ghs = (weekAmountPesewas / 100).ceil();
    return '₵${_formatNumber(ghs)}';
  }

  /// Hours online formatted: 4.5h → "4h 30m"
  String get hoursOnlineDisplay {
    final hours = hoursOnline.floor();
    final minutes = ((hoursOnline - hours) * 60).round();
    if (hours == 0) return '${minutes}m';
    if (minutes == 0) return '${hours}h';
    return '${hours}h ${minutes}m';
  }

  /// Acceptance rate display: "92%"
  String get acceptanceRateDisplay => '${(acceptanceRate * 100).round()}%';
}

String _formatNumber(int number) {
  if (number < 1000) return number.toString();
  final str = number.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
    buffer.write(str[i]);
  }
  return buffer.toString();
}
