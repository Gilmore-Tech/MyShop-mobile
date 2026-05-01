import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../artisan_jobs/providers/artisan_jobs_provider.dart';
import '../../artisan_jobs/providers/submitted_bids_provider.dart';

/// Unsubmitted bid the artisan was filling out. Persisted to SharedPreferences
/// so a kill / crash / accidental dismiss before the backend ACK doesn't
/// silently throw the artisan's typing away.
///
/// Cleared automatically when the job's bid window closes (job leaves
/// `open` / `pendingAdmin` / `adminAssigned`) or when a `SubmittedBid` lands
/// for the same job. See [BidDraftsNotifier.reconcile].
@immutable
class BidDraft {
  const BidDraft({
    required this.jobId,
    required this.savedAt,
    this.clientRequestId,
    this.labourPesewas = 0,
    this.etaMinutes = 0,
    this.durationMinutes = 0,
    this.notes,
    this.attachmentPaths = const [],
    this.submitting = false,
  });

  factory BidDraft.fromJson(Map<String, dynamic> json) => BidDraft(
        jobId: json['jobId'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
        clientRequestId: json['clientRequestId'] as String?,
        labourPesewas: json['labourPesewas'] as int? ?? 0,
        etaMinutes: json['etaMinutes'] as int? ?? 0,
        durationMinutes: json['durationMinutes'] as int? ?? 0,
        notes: json['notes'] as String?,
        attachmentPaths: (json['attachmentPaths'] as List<dynamic>?)
                ?.cast<String>() ??
            const [],
        submitting: json['submitting'] as bool? ?? false,
      );

  final String jobId;
  final DateTime savedAt;

  /// UUID set when the artisan taps SUBMIT BID. Reused on retry so the
  /// backend can dedupe via the `Idempotency-Key` header.
  final String? clientRequestId;

  final int labourPesewas;
  final int etaMinutes;
  final int durationMinutes;
  final String? notes;
  final List<String> attachmentPaths;

  /// True between the moment `_handleSubmit` fires and either ACK or failure.
  /// On cold start, a draft with `submitting=true` triggers reconciliation
  /// against `submittedBidsProvider` + `artisanJobsProvider` to determine
  /// whether the request actually landed.
  final bool submitting;

  bool get hasContent =>
      labourPesewas > 0 ||
      etaMinutes > 0 ||
      durationMinutes > 0 ||
      (notes != null && notes!.isNotEmpty) ||
      attachmentPaths.isNotEmpty;

  BidDraft copyWith({
    String? clientRequestId,
    int? labourPesewas,
    int? etaMinutes,
    int? durationMinutes,
    String? notes,
    List<String>? attachmentPaths,
    bool? submitting,
    DateTime? savedAt,
  }) {
    return BidDraft(
      jobId: jobId,
      savedAt: savedAt ?? this.savedAt,
      clientRequestId: clientRequestId ?? this.clientRequestId,
      labourPesewas: labourPesewas ?? this.labourPesewas,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      notes: notes ?? this.notes,
      attachmentPaths: attachmentPaths ?? this.attachmentPaths,
      submitting: submitting ?? this.submitting,
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'savedAt': savedAt.toIso8601String(),
        if (clientRequestId != null) 'clientRequestId': clientRequestId,
        'labourPesewas': labourPesewas,
        'etaMinutes': etaMinutes,
        'durationMinutes': durationMinutes,
        if (notes != null) 'notes': notes,
        'attachmentPaths': attachmentPaths,
        'submitting': submitting,
      };
}

/// Persists in-progress bid forms keyed by `jobId`. Mirrors the storage
/// shape of [SubmittedBidsNotifier] so the two providers behave the same
/// way at restore / persist time.
class BidDraftsNotifier extends StateNotifier<Map<String, BidDraft>> {
  BidDraftsNotifier(this._ref) : super(const {}) {
    _init();
  }

  final Ref _ref;

  static const _kKey = 'artisan_bid_drafts_v1';

  Future<void> _init() async {
    await _restore();
    // Subscribe to artisanJobsProvider so we reconcile drafts whenever the
    // backend snapshot settles. Reconcile is idempotent: drops drafts whose
    // jobs have left the bid window or already have a submitted bid, and
    // resolves in-flight drafts whose response we never saw last session.
    _ref.listen<ArtisanJobsState>(
      artisanJobsProvider,
      (prev, next) {
        if (!next.isLoading && next.errorMessage == null) {
          reconcile();
        }
      },
      // Fire immediately if the jobs provider is already settled by the
      // time we attach (cold start where someone else read it first).
      fireImmediately: true,
    );
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kKey);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      final map = <String, BidDraft>{};
      for (final item in list) {
        try {
          final draft = BidDraft.fromJson(item as Map<String, dynamic>);
          // Drop any attachment paths that no longer exist on disk — the OS
          // periodically wipes app-temp dirs and we don't want a half-hydrated
          // draft pointing at vanished files.
          final liveAttachments = draft.attachmentPaths
              .where((p) => File(p).existsSync())
              .toList(growable: false);
          map[draft.jobId] = draft.copyWith(attachmentPaths: liveAttachments);
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
      final list = state.values.map((d) => d.toJson()).toList();
      await prefs.setString(_kKey, jsonEncode(list));
    } catch (_) {
      // Best-effort.
    }
  }

  /// Insert or replace the draft for [draft.jobId]. Idempotent.
  Future<void> upsert(BidDraft draft) async {
    state = {...state, draft.jobId: draft};
    await _persist();
  }

  /// Remove the draft (and any associated attachment dir) for [jobId].
  /// No-op when nothing is stored.
  Future<void> remove(String jobId) async {
    if (!state.containsKey(jobId)) return;
    final next = {...state}..remove(jobId);
    state = next;
    await _persist();
  }

  /// Mark the draft as in-flight before firing the HTTP submit. The
  /// `clientRequestId` is the UUID we'll send as `Idempotency-Key` so the
  /// backend can dedupe on retry / replay.
  Future<void> markSubmitting(String jobId, String clientRequestId) async {
    final existing = state[jobId];
    if (existing == null) return;
    final next = existing.copyWith(
      submitting: true,
      clientRequestId: clientRequestId,
      savedAt: DateTime.now(),
    );
    state = {...state, jobId: next};
    await _persist();
  }

  /// Roll the in-flight flag back after a confirmed failure (or after
  /// reconciliation determines the request never landed). The
  /// `clientRequestId` stays attached so a subsequent retry replays the
  /// same idempotency key.
  Future<void> markIdle(String jobId) async {
    final existing = state[jobId];
    if (existing == null || !existing.submitting) return;
    state = {...state, jobId: existing.copyWith(submitting: false)};
    await _persist();
  }

  /// Wipe everything (e.g. on logout). Caller is responsible for clearing
  /// any associated attachment files on disk.
  Future<void> clear() async {
    state = const {};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kKey);
    } catch (_) {}
  }

  BidDraft? byJobId(String jobId) => state[jobId];

  /// One-shot reconcile against `artisanJobsProvider` + `submittedBidsProvider`.
  /// Drops drafts that are stale (job no longer biddable) or already landed
  /// (submitted bid present). Returns the list of `jobId`s the caller should
  /// re-check after a `silentReload()` for in-flight resolution.
  Future<List<String>> reconcile() async {
    final entries = _ref.read(artisanJobsProvider).entries;
    final submitted = _ref.read(submittedBidsProvider);
    final pendingInflight = <String>[];

    for (final draft in [...state.values]) {
      if (submitted.containsKey(draft.jobId)) {
        await remove(draft.jobId);
        continue;
      }

      ArtisanJobEntry? entry;
      for (final e in entries) {
        if (e.job.id == draft.jobId) {
          entry = e;
          break;
        }
      }

      // entry == null can mean two things: the artisan never had this job in
      // the cached list (cold start before /jobs landed), or the backend
      // dropped it (e.g. expired). Keep the draft for now — the next
      // reconcile after `silentReload()` will sort it out.
      if (entry == null) {
        if (draft.submitting && draft.clientRequestId != null) {
          pendingInflight.add(draft.jobId);
        }
        continue;
      }

      final isBiddable = entry.job.status == JobStatus.open ||
          entry.job.status == JobStatus.pendingAdmin ||
          entry.job.status == JobStatus.adminAssigned;
      if (!isBiddable) {
        await remove(draft.jobId);
        continue;
      }

      // Job still biddable but artisan has a `myBid` on it — request landed
      // last session, drop the draft.
      if (entry.hasBid) {
        await remove(draft.jobId);
        continue;
      }

      if (draft.submitting && draft.clientRequestId != null) {
        // Job is biddable, no bid yet — the in-flight request never landed.
        // Roll the flag back so the artisan can retry safely.
        await markIdle(draft.jobId);
      }
    }

    return pendingInflight;
  }
}

final bidDraftsProvider =
    StateNotifierProvider<BidDraftsNotifier, Map<String, BidDraft>>(
  (ref) => BidDraftsNotifier(ref),
);
