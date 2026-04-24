import 'package:dio/dio.dart';

import '../models/api_exception.dart';

/// Service for user-related endpoints beyond auth.
/// EDD § 5.2 — Users (profile, saved locations, emergency contacts)
class UserService {
  UserService(this._dio);
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

  // ── Profile ──────────────────────────────────────────────────────────────────

  /// GET /users/me — Full profile including role sub-profiles.
  Future<Map<String, dynamic>> getMe() async {
    try {
      final response = await _dio.get('/users/me');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PUT /users/me — Update display name, email, language preference.
  Future<Map<String, dynamic>> updateProfile({
    String? fullName,
    String? email,
    String? languagePref,
  }) async {
    try {
      final response = await _dio.put('/users/me', data: {
        if (fullName != null) 'fullName': fullName,
        if (email != null) 'email': email,
        if (languagePref != null) 'languagePref': languagePref,
      },);
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ── Saved Locations ───────────────────────────────────────────────────────────

  /// GET /users/me/saved-locations — List ordered by last_used_at.
  Future<List<dynamic>> getSavedLocations() async {
    try {
      final response = await _dio.get('/users/me/saved-locations');
      return _unwrap(response) as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /users/me/saved-locations — Create a new saved location.
  Future<Map<String, dynamic>> createSavedLocation({
    required String label,
    required String locationType, // 'home' | 'work' | 'favourite'
    required double latitude,
    required double longitude,
    String? addressText,
  }) async {
    try {
      final response = await _dio.post('/users/me/saved-locations', data: {
        'label': label,
        'locationType': locationType,
        'latitude': latitude,
        'longitude': longitude,
        if (addressText != null) 'addressText': addressText,
      },);
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PUT /users/me/saved-locations/:id — Update label, coords, or address.
  Future<Map<String, dynamic>> updateSavedLocation(
    String id, {
    String? label,
    double? latitude,
    double? longitude,
    String? addressText,
  }) async {
    try {
      final response = await _dio.put('/users/me/saved-locations/$id', data: {
        if (label != null) 'label': label,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (addressText != null) 'addressText': addressText,
      },);
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// DELETE /users/me/saved-locations/:id
  Future<void> deleteSavedLocation(String id) async {
    try {
      await _dio.delete('/users/me/saved-locations/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ── Emergency Contacts ────────────────────────────────────────────────────────

  /// GET /users/me/emergency-contacts — List with primary contact first.
  Future<List<dynamic>> getEmergencyContacts() async {
    try {
      final response = await _dio.get('/users/me/emergency-contacts');
      return _unwrap(response) as List<dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /users/me/emergency-contacts — Add a contact (max 3).
  Future<Map<String, dynamic>> createEmergencyContact({
    required String name,
    required String phone,
    String? relationship,
    bool isPrimary = false,
  }) async {
    try {
      final response =
          await _dio.post('/users/me/emergency-contacts', data: {
        'name': name,
        'phone': phone,
        if (relationship != null && relationship.isNotEmpty)
          'relationship': relationship,
        'isPrimary': isPrimary,
      },);
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PUT /users/me/emergency-contacts/:id — Update contact details.
  Future<Map<String, dynamic>> updateEmergencyContact(
    String id, {
    String? name,
    String? phone,
    String? relationship,
    bool? isPrimary,
  }) async {
    try {
      final response =
          await _dio.put('/users/me/emergency-contacts/$id', data: {
        if (name != null) 'name': name,
        if (phone != null) 'phone': phone,
        if (relationship != null) 'relationship': relationship,
        if (isPrimary != null) 'isPrimary': isPrimary,
      },);
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// DELETE /users/me/emergency-contacts/:id
  Future<void> deleteEmergencyContact(String id) async {
    try {
      await _dio.delete('/users/me/emergency-contacts/$id');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ── Loyalty & Referral ────────────────────────────────────────────────────────

  /// GET /users/me/loyalty — Points balance, tier, ledger.
  Future<Map<String, dynamic>> getLoyalty() async {
    try {
      final response = await _dio.get('/users/me/loyalty');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /users/me/referral — Referral code, stats, recent referrals.
  Future<Map<String, dynamic>> getReferral() async {
    try {
      final response = await _dio.get('/users/me/referral');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  // ── Notification Preferences ──────────────────────────────────────────────────

  /// GET /users/me/notification-preferences
  Future<Map<String, dynamic>> getNotificationPreferences() async {
    try {
      final response = await _dio.get('/users/me/notification-preferences');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /users/me/notification-preferences
  Future<void> updateNotificationPreferences({
    bool? pushEnabled,
    bool? smsEnabled,
    bool? emailEnabled,
    bool? criticalSafetyEnabled,
    String? promoFrequency,
  }) async {
    try {
      await _dio.patch('/users/me/notification-preferences', data: {
        if (pushEnabled != null) 'pushEnabled': pushEnabled,
        if (smsEnabled != null) 'smsEnabled': smsEnabled,
        if (emailEnabled != null) 'emailEnabled': emailEnabled,
        if (criticalSafetyEnabled != null)
          'criticalSafetyEnabled': criticalSafetyEnabled,
        if (promoFrequency != null) 'promoFrequency': promoFrequency,
      },);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
