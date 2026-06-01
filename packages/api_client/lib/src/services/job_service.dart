import 'package:dio/dio.dart';
import 'package:shared_models/shared_models.dart';

import '../models/api_exception.dart';

/// Service for artisan marketplace API endpoints.
/// EDD § 5.2 — Marketplace (12 endpoints)
class JobService {
  JobService(this._dio);
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

  /// GET /jobs — List client's jobs with optional filters.
  /// Returns empty list if the endpoint is not yet available (404).
  Future<List<dynamic>> listJobs({
    int page = 1,
    int limit = 50,
    String? status,
    String? search,
  }) async {
    try {
      final response = await _dio.get(
        '/jobs',
        queryParameters: {
          'page': page,
          'limit': limit,
          if (status != null) 'status': status,
          if (search != null && search.isNotEmpty) 'q': search,
        },
      );
      // ignore: avoid_print
      print('[JobService] raw response.data: ${response.data}');
      final body = response.data;
      // Handle various response shapes from the backend.
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        // { success: true, data: [...] }
        if (data is List) return data;
        // { success: true, data: { items: [...] } }
        if (data is Map<String, dynamic>) {
          if (data['items'] is List) return data['items'] as List<dynamic>;
          if (data['jobs'] is List) return data['jobs'] as List<dynamic>;
        }
        // { success: true, data: { data: [...] } } (nested pagination)
        if (data is Map<String, dynamic> && data['data'] is List) {
          return data['data'] as List<dynamic>;
        }
      }
      return [];
    } on DioException catch (e) {
      // Return empty list if endpoint not implemented yet.
      if (e.response?.statusCode == 404) return [];
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /jobs/live-feed — Anonymised platform-wide feed of recent open jobs.
  ///
  /// Used by the provider artisan home "Live Job Feed" carousel as a
  /// social-proof signal. The response is anonymised by the backend (no
  /// client identity, no full address, no description) — every field in
  /// [LiveFeedJob] is safe to display to any artisan. Returns an empty list
  /// on any non-success status so the carousel falls back to the empty-state
  /// placeholder instead of throwing.
  Future<List<LiveFeedJob>> getLiveFeed({int limit = 20}) async {
    try {
      final response = await _dio.get(
        '/jobs/live-feed',
        queryParameters: {'limit': limit},
      );
      final body = response.data;
      List<dynamic> raw = const [];
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is List) raw = data;
      }
      return raw
          .whereType<Map<String, dynamic>>()
          .map(LiveFeedJob.fromJson)
          .toList(growable: false);
    } on DioException catch (e) {
      // Endpoint not yet deployed → empty feed (carousel falls back to
      // the existing "No jobs nearby" empty state).
      if (e.response?.statusCode == 404) return const [];
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /jobs — Create artisan job request.
  Future<Map<String, dynamic>> createJob({
    required String categoryId,
    required String description,
    required double latitude,
    required double longitude,
    String? addressText,
    String? scheduledFor,
    List<String>? photoUrls,
  }) async {
    try {
      final response = await _dio.post(
        '/jobs',
        data: {
          'categoryId': categoryId,
          'description': description,
          'latitude': latitude,
          'longitude': longitude,
          if (addressText != null) 'addressText': addressText,
          if (scheduledFor != null) 'scheduledFor': scheduledFor,
          if (photoUrls != null) 'photos': photoUrls,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /jobs/:id — Get job details.
  Future<Map<String, dynamic>> getJob(String jobId) async {
    try {
      final response = await _dio.get('/jobs/$jobId');
      final data = _unwrap(response) as Map<String, dynamic>;
      // Diagnostic — surface what the backend actually returns for a
      // single-job fetch so we can confirm whether `client: {...}` is
      // present and what shape it has. Remove once the artisan flow is
      // confirmed showing real names end-to-end.
      // ignore: avoid_print
      print(
        '[JobService.getJob] $jobId status=${data['status']} '
        'completedAt=${data['completedAt']} '
        'clientConfirmedCompleteAt=${data['clientConfirmedCompleteAt']} '
        'artisanMarkedCompleteAt=${data['artisanMarkedCompleteAt']} '
        'topKeys=${data.keys.toList()} '
        'client=${data['client']} clientName=${data['clientName']}',
      );
      return data;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /jobs/:id/bids — Artisan: submit a bid on an open job.
  /// Creates a bid record and notifies the client via socket `job:bid_new`.
  ///
  /// Backend expects four fields:
  ///   - `amountPesewas`  (required, int >= 1)
  ///   - `etaMinutes`     (required, int 1–180)
  ///   - `durationMinutes` (required, int 15–1440)
  ///   - `message`        (optional, free-text)
  ///
  /// [clientRequestId] is forwarded as `Idempotency-Key`. Same key on a retry
  /// must return the original response — used to recover from app-kill
  /// between request leaving the device and ACK arriving.
  Future<Map<String, dynamic>> submitBid(
    String jobId, {
    required int amountPesewas,
    required int etaMinutes,
    required int durationMinutes,
    String? notes,
    String? clientRequestId,
  }) async {
    try {
      final payload = <String, dynamic>{
        'amountPesewas': amountPesewas,
        'etaMinutes': etaMinutes,
        'durationMinutes': durationMinutes,
        if (notes != null && notes.trim().isNotEmpty) 'message': notes.trim(),
      };
      // ignore: avoid_print
      print('[JobService] submitBid POST /jobs/$jobId/bids payload=$payload');
      final response = await _dio.post(
        '/jobs/$jobId/bids',
        data: payload,
        options: clientRequestId == null
            ? null
            : Options(headers: {'Idempotency-Key': clientRequestId}),
      );
      // ignore: avoid_print
      print(
        '[JobService] submitBid response=${response.statusCode} data=${response.data}',
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      // ignore: avoid_print
      print('[JobService] submitBid FAILED status=${e.response?.statusCode} '
          'data=${e.response?.data} message=${e.message}');
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:jobId/bids/:bidId — Artisan: revise own pending bid.
  /// Backend mirrors the [submitBid] payload (amount/eta/duration/message);
  /// every field is optional but at least one must change. Rejects with 409
  /// once the client has already selected the bid (`BID_ALREADY_ACCEPTED`)
  /// or the job has moved past bidding (`BID_NOT_PENDING`).
  Future<Map<String, dynamic>> editBid(
    String jobId,
    String bidId, {
    int? amountPesewas,
    int? etaMinutes,
    int? durationMinutes,
    String? notes,
  }) async {
    try {
      final payload = <String, dynamic>{
        if (amountPesewas != null) 'amountPesewas': amountPesewas,
        if (etaMinutes != null) 'etaMinutes': etaMinutes,
        if (durationMinutes != null) 'durationMinutes': durationMinutes,
        if (notes != null && notes.trim().isNotEmpty) 'message': notes.trim(),
      };
      final response = await _dio.patch(
        '/jobs/$jobId/bids/$bidId',
        data: payload,
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// DELETE /jobs/:jobId/bids/:bidId — Artisan: withdraw own pending bid.
  /// Hard-deletes the bid row and emits `job:bid:withdrawn` to the client.
  /// Disallowed once the client has accepted the bid.
  Future<void> withdrawBid(String jobId, String bidId) async {
    try {
      await _dio.delete('/jobs/$jobId/bids/$bidId');
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /jobs/:id/bids — Get bids for a job.
  /// Returns an empty list if the endpoint responds 404.
  Future<List<dynamic>> getBids(String jobId) async {
    try {
      final response = await _dio.get('/jobs/$jobId/bids');
      final body = response.data;
      // Handle the common response shapes:
      //   { success: true, data: [...] }
      //   { success: true, data: { items: [...] } }
      //   { success: true, data: { bids: [...] } }
      //   [...]  (raw array)
      if (body is List) return body;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is List) return data;
        if (data is Map<String, dynamic>) {
          if (data['items'] is List) return data['items'] as List<dynamic>;
          if (data['bids'] is List) return data['bids'] as List<dynamic>;
        }
      }
      return const <dynamic>[];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const <dynamic>[];
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/status — Artisan: advance the job through the active-
  /// work lifecycle. Valid next-statuses (and their required predecessors):
  ///
  ///   confirmed                → artisan_en_route
  ///   artisan_en_route         → arrived
  ///   arrived                  → in_progress
  ///   in_progress              → artisan_marked_complete
  ///
  /// Backend rejects invalid transitions with `INVALID_STATUS_TRANSITION`
  /// (400) and non-assigned artisans with `NOT_ASSIGNED_ARTISAN` (403).
  Future<Map<String, dynamic>> updateJobStatus(
    String jobId, {
    required String status,
  }) async {
    try {
      final response = await _dio.patch(
        '/jobs/$jobId/status',
        data: {'status': status},
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// GET /jobs/:id/bids/locations — Live artisan positions for a job's bids.
  /// Bandwidth-optimised: only the moving fields. Poll every 5–10 s while
  /// the bid review screen is open. Artisans with unknown current location
  /// are omitted from the array — callers fall back to the snapshot.
  /// Returns an empty list on 404 so missing backend support degrades silently.
  Future<List<dynamic>> getBidLocations(String jobId) async {
    try {
      final response = await _dio.get('/jobs/$jobId/bids/locations');
      final body = response.data;
      if (body is List) return body;
      if (body is Map<String, dynamic>) {
        final data = body['data'];
        if (data is List) return data;
        if (data is Map<String, dynamic>) {
          if (data['items'] is List) return data['items'] as List<dynamic>;
          if (data['locations'] is List) {
            return data['locations'] as List<dynamic>;
          }
        }
      }
      return const <dynamic>[];
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return const <dynamic>[];
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/select-bid — Client: accept a bid.
  Future<Map<String, dynamic>> selectBid(
    String jobId, {
    required String bidId,
  }) async {
    try {
      final response = await _dio.patch(
        '/jobs/$jobId/select-bid',
        data: {
          'bidId': bidId,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /jobs/:id/supplement — Artisan: request a material cost supplement
  /// after starting work but before completion. One supplement per job;
  /// backend returns 409 SUPPLEMENT_ALREADY_REQUESTED on a second call.
  /// The client receives an FCM `type=supplement_request` and approves or
  /// rejects via [respondToSupplement] below.
  ///
  /// [amountPesewas] is the EXTRA amount on top of the bid, not the new
  /// total. [reason] is required by the backend and surfaced to the client
  /// in the approve/reject sheet — be specific.
  Future<Map<String, dynamic>> requestSupplement(
    String jobId, {
    required int amountPesewas,
    required String reason,
  }) async {
    try {
      final response = await _dio.post(
        '/jobs/$jobId/supplement',
        data: {
          'amountPesewas': amountPesewas,
          'reason': reason,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/supplement/respond — Client: approve or reject supplement.
  Future<Map<String, dynamic>> respondToSupplement(
    String jobId, {
    required bool approved,
  }) async {
    try {
      final response = await _dio.patch(
        '/jobs/$jobId/supplement/respond',
        data: {
          'approved': approved,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/confirm — Client: confirm job completion (dual confirmation).
  Future<Map<String, dynamic>> confirmJobCompletion(String jobId) async {
    try {
      final response = await _dio.patch('/jobs/$jobId/confirm');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /jobs/:id/artisan-confirm-cash — Artisan: confirm they received
  /// cash off-platform. Backend inserts a `paymentMethod: 'cash'` payment
  /// row, runs the same finalisation path the Paystack webhook does, and
  /// flips the job to `completed`. Returns the updated job (same shape as
  /// GET /jobs/:id).
  ///
  /// Error codes the caller may want to surface:
  ///   - 403 ARTISAN_PROFILE_REQUIRED  — caller has no artisan profile
  ///   - 403 NOT_ASSIGNED_ARTISAN      — caller isn't the assigned artisan
  ///   - 409 PAYSTACK_CHARGE_IN_FLIGHT — let the webhook settle first
  ///   - 409 PAYMENT_RECORD_EXISTS     — non-failed payment row already there
  ///   - 400 JOB_NOT_AWAITING_RECEIPT  — job is in an earlier state
  ///   - 400 AGREED_PRICE_MISSING      — price never recorded on the job
  /// 200 is idempotent: hitting it on an already-completed job returns
  /// the job without writing anything.
  Future<Map<String, dynamic>> artisanConfirmCash(String jobId) async {
    try {
      final response = await _dio.post('/jobs/$jobId/artisan-confirm-cash');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /jobs/:id/dispute — Dispute job (2-hour window).
  Future<Map<String, dynamic>> disputeJob(
    String jobId, {
    required String reason,
    String? description,
  }) async {
    try {
      final response = await _dio.post(
        '/jobs/$jobId/dispute',
        data: {
          'reason': reason,
          if (description != null) 'description': description,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/cancel — Cancel job (30-min free, 20% fee after).
  Future<Map<String, dynamic>> cancelJob(
    String jobId, {
    String? reason,
  }) async {
    try {
      final response = await _dio.patch(
        '/jobs/$jobId/cancel',
        data: {
          if (reason != null) 'reason': reason,
        },
      );
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/confirm-schedule — artisan confirms a scheduled job
  /// within the 24-hour pre-start window. Backend gates on `scheduledFor`
  /// being set and `status` ∈ `{confirmed, artisan_en_route}`. Returns
  /// `{ jobId, artisanConfirmed24h, alreadyConfirmed }` — `alreadyConfirmed`
  /// is `true` when the artisan taps the button twice; the call is
  /// otherwise idempotent.
  Future<Map<String, dynamic>> confirmScheduledJob(String jobId) async {
    try {
      final response = await _dio.patch('/jobs/$jobId/confirm-schedule');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// POST /jobs/:id/escalate — artisan escalates a job stuck in
  /// `artisan_marked_complete` because the client never confirmed. Only
  /// callable after `job_client_confirm_deadline_hours` (default 4h) has
  /// elapsed since the artisan marked complete; backend returns
  /// `ESCALATION_TOO_EARLY` with `remainingMinutes` otherwise.
  ///
  /// On success the job auto-finalises to `completed` and payment is
  /// released to the artisan. Response: `{ jobId, escalated,
  /// artisanMarkedCompleteAt, elapsedMs }`.
  Future<Map<String, dynamic>> escalateJobCompletion(String jobId) async {
    try {
      final response = await _dio.post('/jobs/$jobId/escalate');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// PATCH /jobs/:id/welfare-check/respond — artisan responds to a
  /// 3-hour inactivity welfare ping. Marks the open WelfareCheck row
  /// resolved and resets the job's `lastActivityAt` so the inactivity
  /// clock restarts. Backend returns `NO_OPEN_WELFARE_CHECK` (400) when
  /// there's no unresolved check for the job — typically because the
  /// artisan acted on something else (status update, supplement
  /// request) that already cleared the check.
  ///
  /// Response: `{ welfareCheckId, isResolved }`.
  Future<Map<String, dynamic>> respondToWelfareCheck(String jobId) async {
    try {
      final response = await _dio.patch('/jobs/$jobId/welfare-check/respond');
      return _unwrap(response) as Map<String, dynamic>;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
