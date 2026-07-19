import 'package:dio/dio.dart';

import '../models/api_exception.dart';

enum ProviderAvailabilityRole { driver, artisan }

enum ProviderAvailabilityStatus { online, offline }

enum ProviderLocationHealth { healthy, degraded }

/// Server-authoritative provider availability returned by
/// `GET /providers/me/availability`.
class ProviderAvailabilitySnapshot {
  const ProviderAvailabilitySnapshot({
    required this.role,
    required this.providerId,
    required this.status,
    required this.activeRideId,
    required this.activeJobId,
    required this.lastSeenAt,
    required this.selectedVehicleId,
    required this.locationHealth,
    required this.locationRecoveryRequired,
    required this.locationDegradedAt,
    required this.locationDegradedReason,
    required this.locationDegradedEscalatedAt,
    this.onlineSessionId,
    this.lastLocationSequence,
  });

  factory ProviderAvailabilitySnapshot.fromJson(Map<String, dynamic> json) {
    final role = switch (json['role']) {
      'driver' => ProviderAvailabilityRole.driver,
      'artisan' => ProviderAvailabilityRole.artisan,
      _ => throw const FormatException('Invalid provider availability role'),
    };
    final status = switch (json['status']) {
      'online' => ProviderAvailabilityStatus.online,
      'offline' => ProviderAvailabilityStatus.offline,
      _ => throw const FormatException('Invalid provider availability status'),
    };
    final providerId = json['providerId']?.toString().trim() ?? '';
    if (providerId.isEmpty) {
      throw const FormatException('Missing provider availability providerId');
    }

    String? optionalId(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    final rawLastSeenAt = json['lastSeenAt'];
    final lastSeenAt = rawLastSeenAt is String && rawLastSeenAt.isNotEmpty
        ? DateTime.tryParse(rawLastSeenAt)
        : null;
    if (rawLastSeenAt != null && lastSeenAt == null) {
      throw const FormatException('Invalid provider availability lastSeenAt');
    }

    DateTime? optionalDate(String key) {
      final raw = json[key];
      if (raw == null) return null;
      if (raw is! String || raw.isEmpty) {
        throw FormatException('Invalid provider availability $key');
      }
      final parsed = DateTime.tryParse(raw);
      if (parsed == null) {
        throw FormatException('Invalid provider availability $key');
      }
      return parsed;
    }

    final locationHealth = switch (json['locationHealth']) {
      null => ProviderLocationHealth.healthy,
      'healthy' => ProviderLocationHealth.healthy,
      'degraded' => ProviderLocationHealth.degraded,
      _ => throw const FormatException('Invalid provider location health'),
    };
    final rawRecoveryRequired = json['locationRecoveryRequired'];
    if (rawRecoveryRequired != null && rawRecoveryRequired is! bool) {
      throw const FormatException(
        'Invalid provider location recovery requirement',
      );
    }
    final degradedAt = optionalDate('locationDegradedAt');
    final degradedEscalatedAt = optionalDate('locationDegradedEscalatedAt');
    final onlineSessionId = optionalId('onlineSessionId');
    final rawLastLocationSequence = json['lastLocationSequence'];
    final lastLocationSequence = rawLastLocationSequence is int
        ? rawLastLocationSequence
        : rawLastLocationSequence is num &&
                rawLastLocationSequence.isFinite &&
                rawLastLocationSequence ==
                    rawLastLocationSequence.roundToDouble()
            ? rawLastLocationSequence.toInt()
            : null;
    if (rawLastLocationSequence != null && lastLocationSequence == null) {
      throw const FormatException('Invalid provider location sequence');
    }
    if ((onlineSessionId == null) != (lastLocationSequence == null) ||
        (lastLocationSequence != null && lastLocationSequence < 0)) {
      throw const FormatException('Inconsistent provider location session');
    }
    final recoveryRequired = rawRecoveryRequired as bool? ??
        locationHealth == ProviderLocationHealth.degraded;
    if (recoveryRequired !=
        (locationHealth == ProviderLocationHealth.degraded)) {
      throw const FormatException('Inconsistent provider location health');
    }
    if (locationHealth == ProviderLocationHealth.degraded &&
        degradedAt == null) {
      throw const FormatException('Missing provider location degradedAt');
    }

    return ProviderAvailabilitySnapshot(
      role: role,
      providerId: providerId,
      status: status,
      activeRideId: optionalId('activeRideId'),
      activeJobId: optionalId('activeJobId'),
      lastSeenAt: lastSeenAt,
      selectedVehicleId: optionalId('selectedVehicleId'),
      locationHealth: locationHealth,
      locationRecoveryRequired: recoveryRequired,
      locationDegradedAt: degradedAt,
      locationDegradedReason: optionalId('locationDegradedReason'),
      locationDegradedEscalatedAt: degradedEscalatedAt,
      onlineSessionId: onlineSessionId,
      lastLocationSequence: lastLocationSequence,
    );
  }

  final ProviderAvailabilityRole role;
  final String providerId;
  final ProviderAvailabilityStatus status;
  final String? activeRideId;
  final String? activeJobId;
  final DateTime? lastSeenAt;
  final String? selectedVehicleId;
  final ProviderLocationHealth locationHealth;
  final bool locationRecoveryRequired;
  final DateTime? locationDegradedAt;
  final String? locationDegradedReason;
  final DateTime? locationDegradedEscalatedAt;
  final String? onlineSessionId;
  final int? lastLocationSequence;

  bool get hasActiveWork => activeRideId != null || activeJobId != null;
}

class ProviderVehicleSummary {
  const ProviderVehicleSummary({
    required this.id,
    required this.make,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
    required this.isActive,
    required this.eligible,
    required this.reasonCodes,
  });

  factory ProviderVehicleSummary.fromJson(Map<String, dynamic> json) {
    final id = json['id']?.toString().trim() ?? '';
    if (id.isEmpty) throw const FormatException('Missing provider vehicle id');
    final rawReasons = json['reasonCodes'];
    if (rawReasons is! List || rawReasons.any((value) => value is! String)) {
      throw const FormatException('Invalid provider vehicle reasonCodes');
    }
    if (json['isActive'] is! bool || json['eligible'] is! bool) {
      throw const FormatException('Invalid provider vehicle eligibility state');
    }

    String? optionalText(String key) {
      final value = json[key]?.toString().trim();
      return value == null || value.isEmpty ? null : value;
    }

    final rawYear = json['year'];
    final year = rawYear == null
        ? null
        : rawYear is int
            ? rawYear
            : int.tryParse(rawYear.toString());
    if (rawYear != null && year == null) {
      throw const FormatException('Invalid provider vehicle year');
    }

    return ProviderVehicleSummary(
      id: id,
      make: optionalText('make'),
      model: optionalText('model'),
      year: year,
      plate: optionalText('plate'),
      color: optionalText('color'),
      isActive: json['isActive'] as bool,
      eligible: json['eligible'] as bool,
      reasonCodes: List<String>.unmodifiable(rawReasons.cast<String>()),
    );
  }

  final String id;
  final String? make;
  final String? model;
  final int? year;
  final String? plate;
  final String? color;
  final bool isActive;
  final bool eligible;
  final List<String> reasonCodes;

  String get displayName {
    final name = [make, model].whereType<String>().join(' ').trim();
    return name.isEmpty ? 'Vehicle' : name;
  }
}

class ProviderVehiclePreflight {
  const ProviderVehiclePreflight({
    required this.activeVehicleId,
    required this.onlineStatus,
    required this.legacyBackfillRequired,
    required this.vehicles,
  });

  factory ProviderVehiclePreflight.fromJson(Map<String, dynamic> json) {
    final onlineStatus = json['onlineStatus'];
    if (onlineStatus != 'online' && onlineStatus != 'offline') {
      throw const FormatException('Invalid provider vehicle onlineStatus');
    }
    final legacy = json['legacy'];
    final vehicles = json['vehicles'];
    if (legacy is! Map<String, dynamic> ||
        legacy['backfillRequired'] is! bool ||
        vehicles is! List) {
      throw const FormatException('Invalid provider vehicle preflight');
    }

    final parsedVehicles = vehicles.map((value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid provider vehicle entry');
      }
      return ProviderVehicleSummary.fromJson(value);
    }).toList(growable: false);
    final activeVehicleId = json['activeVehicleId']?.toString().trim();

    return ProviderVehiclePreflight(
      activeVehicleId: activeVehicleId == null || activeVehicleId.isEmpty
          ? null
          : activeVehicleId,
      onlineStatus: onlineStatus as String,
      legacyBackfillRequired: legacy['backfillRequired'] as bool,
      vehicles: List<ProviderVehicleSummary>.unmodifiable(parsedVehicles),
    );
  }

  final String? activeVehicleId;
  final String onlineStatus;
  final bool legacyBackfillRequired;
  final List<ProviderVehicleSummary> vehicles;
}

/// REST access for availability reconciliation after process launch, app
/// resume, socket reconnect, and a server `availability:forced_offline` event.
class ProviderAvailabilityService {
  ProviderAvailabilityService(this._dio);

  final Dio _dio;

  Future<ProviderAvailabilitySnapshot> getMyAvailability() async {
    try {
      final response = await _dio.get('/providers/me/availability');
      return ProviderAvailabilitySnapshot.fromJson(_unwrap(response));
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  /// Changes the authoritative provider availability without requiring a GPS
  /// payload. Offline is the canonical path for clearing a driver's selected
  /// vehicle, including when location permission or cached coordinates vanish.
  Future<ProviderAvailabilitySnapshot> setMyAvailability({
    required ProviderAvailabilityStatus status,
    String? vehicleId,
  }) async {
    try {
      final response = await _dio.post(
        '/providers/availability',
        data: {
          'status': status.name,
          if (vehicleId != null) 'vehicleId': vehicleId,
        },
      );
      return ProviderAvailabilitySnapshot.fromJson(_unwrap(response));
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<ProviderVehiclePreflight> getMyVehicles() async {
    try {
      final response = await _dio.get('/providers/me/vehicles');
      return ProviderVehiclePreflight.fromJson(_unwrap(response));
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Map<String, dynamic> _unwrap(Response<dynamic> response) {
    final body = response.data;
    if (body is Map<String, dynamic> && body['success'] == true) {
      final data = body['data'];
      if (data is Map<String, dynamic>) return data;
    }
    throw FormatException(
      'Unexpected provider availability response from ${response.requestOptions.path}',
    );
  }
}
