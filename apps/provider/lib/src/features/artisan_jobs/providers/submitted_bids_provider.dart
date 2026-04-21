import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Summary of a bid the artisan has placed on a job.
///
/// Stored locally (SharedPreferences) so the "Bids" tab can reliably show
/// bids even when the backend `GET /jobs` response omits `myBid` or drops
/// the job entirely. Merged with the backend record when it does arrive.
///
/// A snapshot of the [Job] at submission time is embedded so the card can
/// render the client name, description, photos, etc. even when the backend
/// never returns the job in its list.
@immutable
class SubmittedBid {
  const SubmittedBid({
    required this.job,
    required this.amountPesewas,
    required this.etaMinutes,
    required this.durationMinutes,
    required this.submittedAt,
    required this.expiresAt,
    this.message,
  });

  factory SubmittedBid.fromJson(Map<String, dynamic> json) {
    // Legacy records stored only the jobId — synthesize a minimal Job so
    // older SharedPreferences data still loads without crashing.
    final jobField = json['job'];
    final job = jobField is Map<String, dynamic>
        ? Job.fromJson(jobField)
        : Job(
            id: json['jobId'] as String,
            status: JobStatus.open,
            categoryId: '',
            description: '',
            latitude: 0,
            longitude: 0,
          );
    return SubmittedBid(
      job: job,
      amountPesewas: json['amountPesewas'] as int,
      etaMinutes: json['etaMinutes'] as int? ?? 0,
      durationMinutes: json['durationMinutes'] as int? ?? 0,
      submittedAt: DateTime.parse(json['submittedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      message: json['message'] as String?,
    );
  }

  final Job job;
  final int amountPesewas;
  final int etaMinutes;
  final int durationMinutes;
  final DateTime submittedAt;
  final DateTime expiresAt;
  final String? message;

  String get jobId => job.id;

  /// Display like `GHS 175.00`.
  String get amountDisplay =>
      'GHS ${(amountPesewas / 100).toStringAsFixed(2)}';

  /// Whether the 5-minute bidding window is still open.
  bool get isActive => DateTime.now().isBefore(expiresAt);

  Map<String, dynamic> toJson() => {
        'jobId': job.id,
        'job': _jobToJson(job),
        'amountPesewas': amountPesewas,
        'etaMinutes': etaMinutes,
        'durationMinutes': durationMinutes,
        'submittedAt': submittedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        if (message != null) 'message': message,
      };
}

/// Serialize a [Job] into a JSON-friendly map. Mirrors [Job.fromJson] so the
/// round-trip restores every field the card needs to render.
Map<String, dynamic> _jobToJson(Job j) => {
      'id': j.id,
      'status': j.status.toJson(),
      'categoryId': j.categoryId,
      if (j.categoryName != null) 'categoryName': j.categoryName,
      'description': j.description,
      'latitude': j.latitude,
      'longitude': j.longitude,
      if (j.addressText != null) 'addressText': j.addressText,
      'photos': j.photos,
      if (j.scheduledFor != null) 'scheduledFor': j.scheduledFor,
      if (j.clientName != null) 'clientName': j.clientName,
      if (j.clientPhone != null) 'clientPhone': j.clientPhone,
      if (j.clientPhotoUrl != null) 'clientPhotoUrl': j.clientPhotoUrl,
      if (j.agreedPricePesewas != null)
        'agreedPricePesewas': j.agreedPricePesewas,
      if (j.shareToken != null) 'shareToken': j.shareToken,
      if (j.artisansNotified != null) 'artisansNotified': j.artisansNotified,
      if (j.createdAt != null) 'createdAt': j.createdAt,
    };

/// Persists the artisan's submitted bids so the "Bids" tab survives app
/// restarts even when the backend response doesn't include `myBid`.
///
/// The map is keyed by `jobId` — one bid per job.
class SubmittedBidsNotifier
    extends StateNotifier<Map<String, SubmittedBid>> {
  SubmittedBidsNotifier() : super(const {}) {
    _restore();
  }

  static const _kKey = 'artisan_submitted_bids';

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final map = <String, SubmittedBid>{};
      for (final item in list) {
        try {
          final bid = SubmittedBid.fromJson(item as Map<String, dynamic>);
          map[bid.jobId] = bid;
        } catch (_) {
          // Skip corrupt entries.
        }
      }
      if (map.isNotEmpty) state = map;
    } catch (_) {
      // Storage unavailable — continue with empty state.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = state.values.map((b) => b.toJson()).toList();
      await prefs.setString(_kKey, jsonEncode(list));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Record a newly submitted bid.
  Future<void> add(SubmittedBid bid) async {
    state = {...state, bid.jobId: bid};
    await _persist();
  }

  /// Remove a bid (e.g. after withdraw, rejection, or expiry).
  Future<void> remove(String jobId) async {
    if (!state.containsKey(jobId)) return;
    final next = {...state}..remove(jobId);
    state = next;
    await _persist();
  }

  /// Clear all bids (e.g. on logout).
  Future<void> clear() async {
    state = const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    } catch (_) {}
  }

  SubmittedBid? byJobId(String jobId) => state[jobId];
}

final submittedBidsProvider =
    StateNotifierProvider<SubmittedBidsNotifier, Map<String, SubmittedBid>>(
  (ref) => SubmittedBidsNotifier(),
);
