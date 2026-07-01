import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';

import '../../../core/di/providers.dart';

// ── Job Detail Data ───────────────────────────────────────────────────────────

class JobActivityDetail {
  final String jobId;
  final String title;
  final String categoryName;
  final String dateTimeLabel;
  final String status;

  // Location
  final String location;

  // Artisan
  final String? artisanName;
  final String? artisanSpecialty;
  final double? artisanRating;
  final int? artisanJobCount;
  final bool artisanVerified;
  final String? artisanPhotoUrl;

  /// Artisan's real, dialable number — exposed on the post-job snapshot for a
  /// limited window so the client can reconnect. Null once it closes.
  final String? artisanPhone;

  // Bids
  final int bidCount;

  // Cost
  final int agreedPricePesewas;
  final int? supplementPesewas;
  final int totalPesewas;
  final String? paymentStatus;

  const JobActivityDetail({
    required this.jobId,
    required this.title,
    required this.categoryName,
    required this.dateTimeLabel,
    required this.status,
    required this.location,
    this.artisanName,
    this.artisanSpecialty,
    this.artisanRating,
    this.artisanJobCount,
    this.artisanVerified = false,
    this.artisanPhotoUrl,
    this.artisanPhone,
    this.bidCount = 0,
    required this.agreedPricePesewas,
    this.supplementPesewas,
    required this.totalPesewas,
    this.paymentStatus,
  });

  String get agreedPriceDisplay => _fmt(agreedPricePesewas);
  String get supplementDisplay => _fmt(supplementPesewas ?? 0);
  String get totalDisplay => _fmt(totalPesewas);

  bool get hasSupplement => supplementPesewas != null && supplementPesewas! > 0;
  bool get hasArtisan => artisanName != null;
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  String get statusLabel => switch (status) {
        'completed' => 'Completed',
        'cancelled' => 'Cancelled',
        'in_progress' => 'In Progress',
        'artisan_marked_complete' => 'Awaiting Confirmation',
        'artisan_en_route' || 'en_route' => 'En Route',
        'arrived' => 'Arrived',
        'confirmed' => 'Confirmed',
        'open' => 'Open',
        _ => 'Pending',
      };
}

String _fmt(int pesewas) {
  final ghs = pesewas / 100;
  if (ghs == ghs.truncateToDouble() && ghs >= 1) {
    return 'GHS ${ghs.toStringAsFixed(0)}';
  }
  return 'GHS ${ghs.toStringAsFixed(2)}';
}

// ── Provider ──────────────────────────────────────────────────────────────────

final jobActivityDetailProvider = AsyncNotifierProvider.autoDispose
    .family<_JobActivityDetailNotifier, JobActivityDetail, String>(
  _JobActivityDetailNotifier.new,
);

class _JobActivityDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<JobActivityDetail, String> {
  @override
  Future<JobActivityDetail> build(String jobId) async {
    final jobService = ref.watch(jobServiceProvider);

    try {
      final job = await jobService.getJob(jobId);
      return _parseJob(jobId, job);
    } on ApiException catch (e) {
      developer.log(
        'getJob detail failed (${e.statusCode}): ${e.message}',
        name: 'JobActivityDetailProvider',
      );
      rethrow;
    }
  }

  JobActivityDetail _parseJob(String jobId, Map<String, dynamic> job) {
    final category =
        job['category'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final artisan =
        job['artisan'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final description = job['description'] as String? ?? '';

    // Format date
    final createdAt = job['createdAt'] as String?;
    String dateTimeLabel = '';
    if (createdAt != null) {
      final dt = DateTime.tryParse(createdAt);
      if (dt != null) {
        dateTimeLabel = DateFormat('MMM d, yyyy · h:mm a').format(dt.toLocal());
      }
    }

    final bids = job['bids'] as List<dynamic>?;
    final bidCount = bids?.length ?? (job['bidCount'] as num?)?.toInt() ?? 0;

    final agreed = (job['agreedPrice'] as num?)?.toInt() ?? 0;
    final supplement = (job['supplementAmount'] as num?)?.toInt();
    final total = agreed + (supplement ?? 0);

    final status = job['status'] as String? ?? 'open';

    // Only surface the artisan's real number while the completed job is
    // inside the 24h post-job contact window. Read-only — no call button.
    final completedAtDt = DateTime.tryParse(
        (job['completedAt'] ?? job['completed_at']) as String? ?? '');
    final rawArtisanPhone =
        (artisan['phone'] ?? artisan['maskedPhone']) as String?;
    final artisanPhone = status == 'completed' &&
            isWithinPostTripContactWindow(completedAtDt) &&
            (rawArtisanPhone?.trim().isNotEmpty ?? false)
        ? rawArtisanPhone
        : null;

    return JobActivityDetail(
      jobId: job['id'] as String? ?? jobId,
      title: description,
      categoryName: category['name'] as String? ?? '',
      dateTimeLabel: dateTimeLabel,
      status: job['status'] as String? ?? 'open',
      location: job['addressText'] as String? ?? '',
      bidCount: bidCount,
      artisanName: artisan['name'] as String?,
      artisanSpecialty:
          artisan['specialty'] as String? ?? category['name'] as String?,
      artisanRating:
          ((artisan['averageRating'] ?? artisan['rating']) as num?)?.toDouble(),
      artisanJobCount: (artisan['completedJobs'] as num?)?.toInt(),
      artisanVerified: artisan['verified'] as bool? ?? false,
      artisanPhotoUrl: artisan['photoUrl'] as String?,
      artisanPhone: (artisan['phone'] ?? artisan['maskedPhone']) as String?,
      agreedPricePesewas: agreed,
      supplementPesewas: supplement,
      totalPesewas: total,
      paymentStatus: job['paymentStatus'] as String?,
    );
  }
}
