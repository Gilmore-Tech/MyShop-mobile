import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';

// ── Job Status ────────────────────────────────────────────────────────────────
// EDD § 7.1 Job Request & Bid Lifecycle.
// Status progression: queued → pending → bids_received → selecting_artisan
//                     → confirmed → en_route → arrived → in_progress
//                     → completed | cancelled

enum JobStatus {
  queued,
  open,
  // `pendingAdmin` and `adminAssigned` are the no-bids escalation path —
  // when the bid window expires with 0 bids, the backend flips the job
  // to `pending_admin`; an admin then re-routes it (or the cron fans out
  // to a wider radius) and it becomes `admin_assigned`. The client used
  // to fall through to `JobStatus.open` here and display "Pending" with
  // no distinct treatment — keeping the rider stuck thinking artisans
  // were still bidding. See bid.service.ts::expireBidWindows.
  pendingAdmin,
  adminAssigned,
  confirmed,
  enRoute,
  arrived,
  inProgress,
  artisanMarkedComplete,
  pendingPayment,
  completed,
  cancelled,
}

extension JobStatusX on JobStatus {
  String get displayLabel => switch (this) {
        JobStatus.queued => 'Queued',
        JobStatus.open => 'Open',
        JobStatus.pendingAdmin => 'No bids yet — review',
        JobStatus.adminAssigned => 'Artisan assigned',
        JobStatus.confirmed => 'Confirmed',
        JobStatus.enRoute => 'En Route',
        JobStatus.arrived => 'Arrived',
        JobStatus.inProgress => 'In Progress',
        JobStatus.artisanMarkedComplete => 'Awaiting Confirmation',
        JobStatus.pendingPayment => 'Processing Payment',
        JobStatus.completed => 'Completed',
        JobStatus.cancelled => 'Cancelled',
      };

  Color get badgeColor => switch (this) {
        JobStatus.completed => MyShopColors.success,
        JobStatus.cancelled => MyShopColors.error,
        JobStatus.inProgress => MyShopColors.primaryGold,
        JobStatus.artisanMarkedComplete => MyShopColors.primaryGold,
        JobStatus.pendingPayment => MyShopColors.primaryGold,
        JobStatus.enRoute => MyShopColors.primaryGold,
        JobStatus.arrived => MyShopColors.primaryGold,
        JobStatus.confirmed => MyShopColors.success,
        // Surface the no-bids escalation distinctly from the "open and
        // still collecting bids" state — uses the warning amber so the
        // rider can tell something needs attention without it looking
        // like an outright failure.
        JobStatus.pendingAdmin => MyShopColors.warning,
        JobStatus.adminAssigned => MyShopColors.info,
        _ => MyShopColors.warning,
      };
}

// ── Timeline Step ─────────────────────────────────────────────────────────────
// Represents a single step in the Request Timeline displayed on the detail screen.

enum TimelineStepStatus { completed, active, pending }

class TimelineStep {
  final String title;
  final TimelineStepStatus status;

  /// Formatted time string, e.g. "TODAY, 09:15 AM". Null for future steps.
  final String? timeLabel;

  /// Subtitle badge text shown for active/pending steps, e.g. "IN PROGRESS".
  final String? badgeLabel;

  /// Supporting description for the step.
  final String description;

  const TimelineStep({
    required this.title,
    required this.status,
    this.timeLabel,
    this.badgeLabel,
    required this.description,
  });
}

// ── Bid Summary ───────────────────────────────────────────────────────────────
// Lightweight model for the bid count and artisan avatar stack shown in the card.

class BidSummary {
  final int count;

  /// Up to 3 placeholder colours for the avatar stack.
  final List<Color> avatarColors;

  const BidSummary({required this.count, required this.avatarColors});
}

// ── Job Detail ────────────────────────────────────────────────────────────────
// Full detail model for a single artisan job request.
// API: GET /v1/jobs/:id (EDD § Marketplace Endpoints)

class JobDetail {
  final String id;
  final String title;
  final String categoryName;
  final IconData categoryIcon;
  final String location;

  /// Job-site coordinates (WGS84). Zero when the backend didn't send them —
  /// callers should check [hasCoordinates] before using.
  final double latitude;
  final double longitude;

  final JobStatus status;
  final bool isImmediate;

  /// Only set when [isImmediate] is false — the scheduled appointment time.
  final DateTime? scheduledFor;

  final String description;

  /// URLs of reference photos attached to this job.
  final List<String> photoUrls;

  final BidSummary bids;
  final List<TimelineStep> timeline;

  /// Artisan ID assigned after the client selects a bid. Null while the job
  /// is still open / queued. Used to resolve the accepted bid for display.
  final String? selectedArtisanId;

  /// ISO timestamp set by the backend when the client picks a payment
  /// method on the payment screen. For cash, the job stays at
  /// `artisan_marked_complete` server-side until the artisan taps "Yes,
  /// I received payment", so the action bar must look at this field —
  /// not just `status` — to avoid prompting the client to pay again.
  final String? clientPaymentAcknowledgedAt;

  /// `'cash' | 'momo' | 'card'` — null until acknowledged. Lets the UI
  /// tell a cash wait apart from a Paystack-in-flight wait.
  final String? clientPaymentMethod;

  const JobDetail({
    required this.id,
    required this.title,
    required this.categoryName,
    required this.categoryIcon,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.isImmediate,
    this.scheduledFor,
    required this.description,
    required this.photoUrls,
    required this.bids,
    required this.timeline,
    this.selectedArtisanId,
    this.clientPaymentAcknowledgedAt,
    this.clientPaymentMethod,
  });

  /// True when the client has acknowledged payment (any method) but the
  /// job hasn't settled yet. Drives the "waiting for artisan" tile so the
  /// client isn't re-prompted to pay on back-navigation.
  bool get isPaymentAcknowledgedPending =>
      status == JobStatus.artisanMarkedComplete &&
      clientPaymentAcknowledgedAt != null &&
      clientPaymentAcknowledgedAt!.isNotEmpty;

  bool get hasCoordinates => latitude != 0 && longitude != 0;

  /// True once the client has selected a bid and the backend has confirmed the
  /// assignment. After this point the job detail screen swaps "View Bids" for
  /// "View Selected Bid".
  bool get hasSelectedArtisan =>
      selectedArtisanId != null && selectedArtisanId!.isNotEmpty;
}

// ── Provider ──────────────────────────────────────────────────────────────────

final jobDetailProvider = AsyncNotifierProvider.autoDispose
    .family<_JobDetailNotifier, JobDetail, String>(
  _JobDetailNotifier.new,
);

class _JobDetailNotifier
    extends AutoDisposeFamilyAsyncNotifier<JobDetail, String> {
  @override
  Future<JobDetail> build(String jobId) async {
    final jobService = ref.watch(jobServiceProvider);
    try {
      final data = await jobService.getJob(jobId);
      return _parseJobDetail(data);
    } on ApiException catch (e) {
      // 429 means the polling + socket-driven refetches outpaced the
      // backend's throttler. Holding onto the previous snapshot keeps the
      // timeline visible — the next poll tick will pick up the real state.
      if (e.statusCode == 429) {
        final previous = state.valueOrNull;
        if (previous != null) return previous;
      }
      rethrow;
    }
  }

  /// Parse API response into [JobDetail].
  JobDetail _parseJobDetail(Map<String, dynamic> data) {
    final status = _parseJobStatus(data['status'] as String? ?? 'pending');

    // Bid count may arrive in several shapes from the backend.
    int bidCount = 0;
    if (data['bidsCount'] is num) {
      bidCount = (data['bidsCount'] as num).toInt();
    } else if (data['bidCount'] is num) {
      bidCount = (data['bidCount'] as num).toInt();
    } else if (data['bids'] is List) {
      bidCount = (data['bids'] as List).length;
    } else if (data['bids'] is Map && (data['bids'] as Map)['count'] is num) {
      bidCount = ((data['bids'] as Map)['count'] as num).toInt();
    }

    // Category name: prefer the `category` object, fall back to a flat field.
    final categoryName =
        (data['category'] as Map<String, dynamic>?)?['name'] as String? ??
            data['categoryName'] as String? ??
            '';

    // Title + description may be merged as "title\n\ndescription" (legacy),
    // or sent as separate `title` / `description` fields.
    final rawTitle = data['title'] as String?;
    final rawDescription = data['description'] as String? ?? '';
    final String title;
    final String description;
    if (rawTitle != null && rawTitle.isNotEmpty) {
      title = rawTitle;
      description = rawDescription;
    } else {
      final splitIndex = rawDescription.indexOf('\n\n');
      title = splitIndex > 0
          ? rawDescription.substring(0, splitIndex)
          : rawDescription;
      description =
          splitIndex > 0 ? rawDescription.substring(splitIndex + 2) : '';
    }

    final clientPaymentAck =
        data['clientPaymentAcknowledgedAt'] as String?;
    final clientPaymentMethod = data['clientPaymentMethod'] as String?;

    // When the client has acknowledged payment but the job hasn't been
    // marked completed yet (cash flow waiting on the artisan, or a
    // Paystack charge that hasn't webhooked), advance the timeline to
    // "Processing Payment" so the user sees forward motion instead of
    // sitting on "Awaiting Confirmation". The action bar still uses the
    // raw `status` + ack to pick the right tile.
    final timelineStatus =
        status == JobStatus.artisanMarkedComplete &&
                clientPaymentAck != null &&
                clientPaymentAck.isNotEmpty
            ? JobStatus.pendingPayment
            : status;

    return JobDetail(
      id: data['id'] as String? ?? data['jobId'] as String? ?? '',
      title: title,
      categoryName: categoryName,
      categoryIcon: _categoryIcon(categoryName),
      location: data['addressText'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      status: status,
      isImmediate: data['scheduledFor'] == null,
      scheduledFor: data['scheduledFor'] != null
          ? DateTime.tryParse(data['scheduledFor'] as String)
          : null,
      description: description,
      photoUrls: (data['photos'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      bids: BidSummary(
        count: bidCount,
        avatarColors: const [
          Color(0xFF5D4037),
          Color(0xFF795548),
          Color(0xFF607D8B),
        ],
      ),
      timeline: _buildTimeline(timelineStatus),
      selectedArtisanId: data['artisanId'] as String?,
      clientPaymentAcknowledgedAt: clientPaymentAck,
      clientPaymentMethod: clientPaymentMethod,
    );
  }

  static IconData _categoryIcon(String categoryName) {
    final lower = categoryName.toLowerCase();
    if (lower.contains('plumb')) return Icons.plumbing;
    if (lower.contains('electr')) return Icons.electrical_services;
    if (lower.contains('carpen') || lower.contains('wood')) {
      return Icons.carpenter;
    }
    if (lower.contains('paint')) return Icons.format_paint;
    if (lower.contains('clean')) return Icons.cleaning_services;
    if (lower.contains('tow') || lower.contains('car')) return Icons.car_repair;
    if (lower.contains('repair')) return Icons.build_rounded;
    if (lower.contains('delivery') || lower.contains('package')) {
      return Icons.local_shipping;
    }
    if (lower.contains('tailor') ||
        lower.contains('fashion') ||
        lower.contains('dress')) {
      return Icons.checkroom;
    }
    return Icons.handyman_rounded;
  }

  static JobStatus _parseJobStatus(String status) {
    return switch (status) {
      'queued' => JobStatus.queued,
      'open' => JobStatus.open,
      'pending_admin' || 'admin_review' => JobStatus.pendingAdmin,
      'admin_assigned' || 'awaiting_artisan_quote' => JobStatus.adminAssigned,
      'confirmed' => JobStatus.confirmed,
      'artisan_en_route' || 'en_route' => JobStatus.enRoute,
      'arrived' => JobStatus.arrived,
      'in_progress' => JobStatus.inProgress,
      'artisan_marked_complete' => JobStatus.artisanMarkedComplete,
      'pending_payment' => JobStatus.pendingPayment,
      'completed' => JobStatus.completed,
      'cancelled' => JobStatus.cancelled,
      _ => JobStatus.open,
    };
  }

  static List<TimelineStep> _buildTimeline(JobStatus status) {
    // Skip cancelled — it's a terminal state shown via the status badge.
    if (status == JobStatus.cancelled) {
      return const [
        TimelineStep(
          title: 'Cancelled',
          status: TimelineStepStatus.active,
          badgeLabel: 'CANCELLED',
          description: 'This job request has been cancelled.',
        ),
      ];
    }

    final steps = <TimelineStep>[];
    final statusIndex = JobStatus.values.indexOf(status);

    final allSteps = [
      (
        JobStatus.queued,
        'Request Posted',
        'Your service request was posted to the marketplace.'
      ),
      (
        JobStatus.open,
        'Awaiting Bids',
        'Artisans in your area are reviewing your request.'
      ),
      (
        JobStatus.confirmed,
        'Artisan Confirmed',
        'An artisan has been assigned to your job.'
      ),
      (
        JobStatus.enRoute,
        'En Route',
        'The artisan is on their way to your location.'
      ),
      (
        JobStatus.arrived,
        'Arrived',
        'The artisan has arrived at your location.'
      ),
      (JobStatus.inProgress, 'In Progress', 'Work is underway.'),
      (
        JobStatus.artisanMarkedComplete,
        'Awaiting Confirmation',
        'The artisan has marked the job complete. Please confirm.'
      ),
      (
        JobStatus.pendingPayment,
        'Processing Payment',
        'Your payment is being processed. This usually takes a few seconds.'
      ),
      (
        JobStatus.completed,
        'Completed',
        'The job has been completed successfully.'
      ),
    ];

    for (final (stepStatus, title, desc) in allSteps) {
      final stepIndex = JobStatus.values.indexOf(stepStatus);
      final TimelineStepStatus tss;
      if (stepIndex < statusIndex) {
        tss = TimelineStepStatus.completed;
      } else if (stepIndex == statusIndex) {
        tss = TimelineStepStatus.active;
      } else {
        tss = TimelineStepStatus.pending;
      }
      steps.add(TimelineStep(
        title: title,
        status: tss,
        badgeLabel: tss == TimelineStepStatus.active ? 'CURRENT' : null,
        description: desc,
      ));
    }
    return steps;
  }
}
