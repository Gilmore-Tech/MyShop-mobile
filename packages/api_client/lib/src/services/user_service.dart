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

  /// DELETE /users/me — Permanently delete the authenticated user's account.
  /// Backend cascades to bookings/payments/etc. per its retention policy.
  /// Caller is responsible for clearing local tokens and routing to the
  /// auth screen on success.
  Future<void> deleteAccount() async {
    try {
      await _dio.delete('/users/me');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /users/me/ghana-card — Submit Ghana Card for client KYC review.
  ///
  /// Caller must first upload the card image via [MediaService.uploadImage]
  /// (`purpose: 'profile_photo'` per the backend DTO) and pass the resulting
  /// hosted URL as [documentImageUrl]. The card number must match the
  /// `GHA-XXXXXXXXX-X` pattern — the backend rejects anything else.
  ///
  /// Sets `client.kycStatus='pending_review'` server-side. Verification is
  /// async (manual admin review) — clients poll `GET /users/me` and watch for
  /// `client.ghanaCardVerified` to flip to `true`, or `kycStatus` to flip to
  /// `'rejected'` with [ClientProfile.kycRejectionReason] populated.
  ///
  /// Possible 4xx error codes:
  ///   • `INVALID_GHANA_CARD_NUMBER` — number format wrong
  ///   • `ENCRYPTION_UNAVAILABLE`    — backend secret missing
  ///   • `CLIENT_PROFILE_REQUIRED`   — caller has no Client row
  ///   • `KYC_IN_PROGRESS`           — already submitted, awaiting review
  ///   • `KYC_ALREADY_VERIFIED`      — verified already, nothing to do
  Future<Map<String, dynamic>> submitClientGhanaCard({
    required String documentImageUrl,
    required String ghanaCardNumber,
  }) async {
    try {
      final response = await _dio.post(
        '/users/me/ghana-card',
        data: {
          'documentImageUrl': documentImageUrl,
          'ghanaCardNumber':  ghanaCardNumber,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /users/me/profile-photo — Persist the client's profile photo URL.
  ///
  /// The URL must already be hosted (i.e. a CDN/Cloudinary URL returned by
  /// `MediaService.uploadProfilePhoto`); this endpoint just attaches the URL
  /// to the `Client` row server-side. Returns the full updated profile so
  /// callers can refresh state from one response.
  Future<Map<String, dynamic>> updateClientProfilePhoto({
    required String profilePhotoUrl,
  }) async {
    try {
      final response = await _dio.post(
        '/users/me/profile-photo',
        data: {'profilePhotoUrl': profilePhotoUrl},
      );
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

  // ── Referral ──────────────────────────────────────────────────────────────────
  // Loyalty endpoints live on [LoyaltyService] (`/v1/loyalty/*`). The
  // points balance itself is read off the user profile via [getMe].

  /// GET /users/me/referral — Referral code, stats, recent referrals.
  Future<Map<String, dynamic>> getReferral() async {
    try {
      final response = await _dio.get('/users/me/referral');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

}
