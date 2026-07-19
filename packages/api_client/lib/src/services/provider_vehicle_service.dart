import 'package:dio/dio.dart';

import '../models/api_exception.dart';

enum ProviderVehicleApprovalStatus {
  pendingCoordinator,
  coordinatorApproved,
  approved,
  rejected,
  retired,
}

enum ProviderVehicleCategoryStatus { pending, approved, rejected }

ProviderVehicleApprovalStatus _approvalStatus(Object? value) => switch (value) {
      'pending_coordinator' => ProviderVehicleApprovalStatus.pendingCoordinator,
      'coordinator_approved' =>
        ProviderVehicleApprovalStatus.coordinatorApproved,
      'approved' => ProviderVehicleApprovalStatus.approved,
      'rejected' => ProviderVehicleApprovalStatus.rejected,
      'retired' => ProviderVehicleApprovalStatus.retired,
      _ => throw const FormatException('Invalid vehicle approval status'),
    };

ProviderVehicleCategoryStatus _categoryStatus(Object? value) => switch (value) {
      'pending' => ProviderVehicleCategoryStatus.pending,
      'approved' => ProviderVehicleCategoryStatus.approved,
      'rejected' => ProviderVehicleCategoryStatus.rejected,
      _ => throw const FormatException('Invalid vehicle category status'),
    };

class ProviderVehicleCategoryAssignment {
  const ProviderVehicleCategoryAssignment({
    required this.id,
    required this.name,
    required this.slug,
    required this.isActive,
    required this.status,
    required this.rejectionReason,
    required this.reviewedAt,
  });

  factory ProviderVehicleCategoryAssignment.fromJson(
    Map<String, dynamic> json,
  ) {
    return ProviderVehicleCategoryAssignment(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      slug: _requiredString(json, 'slug'),
      isActive: _requiredBool(json, 'isActive'),
      status: _categoryStatus(json['status']),
      rejectionReason: _optionalString(json, 'rejectionReason'),
      reviewedAt: _optionalDate(json, 'reviewedAt'),
    );
  }

  final String id;
  final String name;
  final String slug;
  final bool isActive;
  final ProviderVehicleCategoryStatus status;
  final String? rejectionReason;
  final DateTime? reviewedAt;
}

class ProviderVehicleRevision {
  const ProviderVehicleRevision({
    required this.id,
    required this.version,
    required this.status,
    required this.make,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
    required this.rideCategoryIds,
    required this.rejectionReason,
  });

  factory ProviderVehicleRevision.fromJson(Map<String, dynamic> json) {
    final rawCategoryIds = json['rideCategoryIds'];
    if (rawCategoryIds is! List ||
        rawCategoryIds.any((value) => value is! String)) {
      throw const FormatException('Invalid vehicle revision category IDs');
    }
    final status = _approvalStatus(json['status']);
    if (status != ProviderVehicleApprovalStatus.pendingCoordinator &&
        status != ProviderVehicleApprovalStatus.coordinatorApproved) {
      throw const FormatException('Invalid open vehicle revision status');
    }
    return ProviderVehicleRevision(
      id: _requiredString(json, 'id'),
      version: _requiredInt(json, 'version'),
      status: status,
      make: _requiredString(json, 'make'),
      model: _requiredString(json, 'model'),
      year: _requiredInt(json, 'year'),
      plate: _requiredString(json, 'plate'),
      color: _requiredString(json, 'color'),
      rideCategoryIds: List<String>.unmodifiable(rawCategoryIds.cast<String>()),
      rejectionReason: _optionalString(json, 'rejectionReason'),
    );
  }

  final String id;
  final int version;
  final ProviderVehicleApprovalStatus status;
  final String make;
  final String model;
  final int year;
  final String plate;
  final String color;
  final List<String> rideCategoryIds;
  final String? rejectionReason;
}

class ProviderVehicle {
  const ProviderVehicle({
    required this.id,
    required this.make,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
    required this.isActive,
    required this.approvalStatus,
    required this.version,
    required this.rejectionReason,
    required this.coordinatorReviewedAt,
    required this.regionalManagerReviewedAt,
    required this.retirementRequestedAt,
    required this.retirementRequestReason,
    required this.rideCategories,
    required this.pendingRevision,
    required this.eligible,
    required this.reasonCodes,
  });

  factory ProviderVehicle.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['rideCategories'];
    final rawReasons = json['reasonCodes'];
    if (rawCategories is! List || rawReasons is! List) {
      throw const FormatException('Invalid vehicle collections');
    }
    final pendingRevision = json['pendingRevision'];
    if (pendingRevision != null && pendingRevision is! Map) {
      throw const FormatException('Invalid pending vehicle revision');
    }
    if (rawReasons.any((value) => value is! String)) {
      throw const FormatException('Invalid vehicle reason codes');
    }
    return ProviderVehicle(
      id: _requiredString(json, 'id'),
      make: _requiredString(json, 'make'),
      model: _requiredString(json, 'model'),
      year: _requiredInt(json, 'year'),
      plate: _requiredString(json, 'plate'),
      color: _requiredString(json, 'color'),
      isActive: _requiredBool(json, 'isActive'),
      approvalStatus: _approvalStatus(json['approvalStatus']),
      version: _requiredInt(json, 'version'),
      rejectionReason: _optionalString(json, 'rejectionReason'),
      coordinatorReviewedAt: _optionalDate(json, 'coordinatorReviewedAt'),
      regionalManagerReviewedAt:
          _optionalDate(json, 'regionalManagerReviewedAt'),
      retirementRequestedAt: _optionalDate(json, 'retirementRequestedAt'),
      retirementRequestReason: _optionalString(json, 'retirementRequestReason'),
      rideCategories: List<ProviderVehicleCategoryAssignment>.unmodifiable(
        rawCategories.map(
          (value) => ProviderVehicleCategoryAssignment.fromJson(
            _stringMap(value, 'vehicle ride category'),
          ),
        ),
      ),
      pendingRevision: pendingRevision == null
          ? null
          : ProviderVehicleRevision.fromJson(
              Map<String, dynamic>.from(pendingRevision),
            ),
      eligible: _requiredBool(json, 'eligible'),
      reasonCodes: List<String>.unmodifiable(rawReasons.cast<String>()),
    );
  }

  final String id;
  final String make;
  final String model;
  final int year;
  final String plate;
  final String color;
  final bool isActive;
  final ProviderVehicleApprovalStatus approvalStatus;
  final int version;
  final String? rejectionReason;
  final DateTime? coordinatorReviewedAt;
  final DateTime? regionalManagerReviewedAt;
  final DateTime? retirementRequestedAt;
  final String? retirementRequestReason;
  final List<ProviderVehicleCategoryAssignment> rideCategories;
  final ProviderVehicleRevision? pendingRevision;
  final bool eligible;
  final List<String> reasonCodes;

  String get displayName => '$make $model';
  bool get removalRequested => retirementRequestedAt != null;
}

class ProviderVehiclesResponse {
  const ProviderVehiclesResponse({
    required this.activeVehicleId,
    required this.onlineStatus,
    required this.legacyBackfillRequired,
    required this.legacyReasonCode,
    required this.vehicles,
  });

  factory ProviderVehiclesResponse.fromJson(Map<String, dynamic> json) {
    final legacy = _stringMap(json['legacy'], 'vehicle legacy state');
    final rawVehicles = json['vehicles'];
    if (rawVehicles is! List) {
      throw const FormatException('Invalid vehicles list');
    }
    final onlineStatus = _requiredString(json, 'onlineStatus');
    if (onlineStatus != 'online' && onlineStatus != 'offline') {
      throw const FormatException('Invalid vehicle online status');
    }
    return ProviderVehiclesResponse(
      activeVehicleId: _optionalString(json, 'activeVehicleId'),
      onlineStatus: onlineStatus,
      legacyBackfillRequired: _requiredBool(legacy, 'backfillRequired'),
      legacyReasonCode: _optionalString(legacy, 'reasonCode'),
      vehicles: List<ProviderVehicle>.unmodifiable(
        rawVehicles.map(
          (value) => ProviderVehicle.fromJson(
            _stringMap(value, 'provider vehicle'),
          ),
        ),
      ),
    );
  }

  final String? activeVehicleId;
  final String onlineStatus;
  final bool legacyBackfillRequired;
  final String? legacyReasonCode;
  final List<ProviderVehicle> vehicles;
}

class ProviderRideCategoryChoice {
  const ProviderRideCategoryChoice({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
  });

  factory ProviderRideCategoryChoice.fromJson(Map<String, dynamic> json) {
    if (!_requiredBool(json, 'isActive')) {
      throw const FormatException('Inactive category in active category list');
    }
    return ProviderRideCategoryChoice(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      slug: _requiredString(json, 'slug'),
      description: _optionalString(json, 'description') ?? '',
    );
  }

  final String id;
  final String name;
  final String slug;
  final String description;
}

class ProviderVehicleInput {
  const ProviderVehicleInput({
    required this.make,
    required this.model,
    required this.year,
    required this.plate,
    required this.color,
    required this.rideCategoryIds,
  });

  final String make;
  final String model;
  final int year;
  final String plate;
  final String color;
  final List<String> rideCategoryIds;

  Map<String, dynamic> toJson() => {
        'make': make,
        'model': model,
        'year': year,
        'plate': plate,
        'color': color,
        'rideCategoryIds': rideCategoryIds,
      };
}

class ProviderVehicleMutationResult {
  const ProviderVehicleMutationResult({
    required this.vehicleId,
    required this.version,
  });

  final String vehicleId;
  final int version;
}

class ProviderVehicleService {
  ProviderVehicleService(this._dio);

  final Dio _dio;

  Future<ProviderVehiclesResponse> listMyVehicles() async {
    try {
      final response = await _dio.get('/providers/me/vehicles');
      return ProviderVehiclesResponse.fromJson(_unwrapMap(response));
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<List<ProviderRideCategoryChoice>> listActiveRideCategories() async {
    try {
      final response = await _dio.get('/ride-categories');
      final data = _unwrap(response);
      if (data is! List) {
        throw const FormatException('Invalid active ride category response');
      }
      return List<ProviderRideCategoryChoice>.unmodifiable(
        data.map(
          (value) => ProviderRideCategoryChoice.fromJson(
            _stringMap(value, 'ride category'),
          ),
        ),
      );
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<ProviderVehicleMutationResult> createVehicle(
    ProviderVehicleInput input,
  ) async {
    try {
      final response = await _dio.post(
        '/providers/me/vehicles',
        data: input.toJson(),
      );
      return _mutationResult(response);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<ProviderVehicleMutationResult> updateVehicle({
    required String vehicleId,
    required int expectedVersion,
    required ProviderVehicleInput input,
  }) async {
    try {
      final response = await _dio.patch(
        '/providers/me/vehicles/$vehicleId',
        data: {...input.toJson(), 'expectedVersion': expectedVersion},
      );
      return _mutationResult(response);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  Future<ProviderVehicleMutationResult> requestRemoval({
    required String vehicleId,
    required int expectedVersion,
    String? reason,
  }) async {
    try {
      final response = await _dio.post(
        '/providers/me/vehicles/$vehicleId/removal-request',
        data: {
          'expectedVersion': expectedVersion,
          if (reason != null && reason.trim().isNotEmpty)
            'reason': reason.trim(),
        },
      );
      return _mutationResult(response);
    } on DioException catch (error) {
      throw ApiException.fromDioException(error);
    }
  }

  ProviderVehicleMutationResult _mutationResult(Response<dynamic> response) {
    final data = _unwrapMap(response);
    final vehicle = _stringMap(data['vehicle'], 'vehicle mutation result');
    return ProviderVehicleMutationResult(
      vehicleId: _requiredString(vehicle, 'id'),
      version: _requiredInt(vehicle, 'version'),
    );
  }

  Map<String, dynamic> _unwrapMap(Response<dynamic> response) {
    final data = _unwrap(response);
    return _stringMap(data, 'API data');
  }

  dynamic _unwrap(Response<dynamic> response) {
    final body = response.data;
    if (body is Map && body['success'] == true && body.containsKey('data')) {
      return body['data'];
    }
    throw FormatException(
      'Unexpected provider vehicle response from ${response.requestOptions.path}',
    );
  }
}

Map<String, dynamic> _stringMap(Object? value, String label) {
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('Invalid $label');
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.trim().isNotEmpty) return value.trim();
  throw FormatException('Invalid $key');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value.trim().isEmpty ? null : value.trim();
  throw FormatException('Invalid $key');
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('Invalid $key');
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  throw FormatException('Invalid $key');
}

DateTime? _optionalDate(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('Invalid $key');
}
